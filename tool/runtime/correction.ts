import type { createZipformerSession } from '@pinned/session';
import { costTable } from '@pinned/phonemeCost';
import { normalizedDistance } from '@pinned/alignment';
import { stripPreambles, preamblePending } from '@pinned/search';

type Session = Awaited<ReturnType<typeof createZipformerSession>>;
type Action = Parameters<Session['correct']>[0];

export function setExpected(session: Session, value: unknown) {
  if (value == null) { session.setExpected(null); return; }
  const passage = value as { surah: number; ayah: number; ayahEnd?: number };
  const { surah, ayah } = passage;
  const end = passage.ayahEnd ?? ayah;
  if (!Number.isInteger(surah) || surah < 1 || surah > 114 ||
      !Number.isInteger(ayah) || ayah < 1 || !Number.isInteger(end) || end < ayah ||
      !(session.wordCount(surah, ayah) > 0) || !(session.wordCount(surah, end) > 0)) {
    throw new Error('Expected passage outside pinned corpus');
  }
  session.setExpected({ surah, ayah, ayahEnd: end });
}

export function correct(session: Session, value: unknown) {
  const action = value as Action;
  const phase = session.correction.state.phase;
  const allowed = action === 'retry' ? phase === 'error' || phase === 'corrected'
    : action === 'stop_retry' ? phase === 'retrying'
    : action === 'dismiss' ? phase === 'error'
    : action === 'continue' ? phase === 'corrected'
    : action === 'review_later' || action === 'close' ? phase !== 'idle' : false;
  if (!allowed) throw new Error('Correction action is not valid in this phase');
  session.correct(action); // onEvent is the sole event ingestion path.
}

function deferOpenIssues(session: Session) {
  // Structural checks can queue several findings. Closing one may raise the
  // next; a single close would still leave upstream stop() unable to finalize.
  while (session.correction.state.phase !== 'idle') {
    const attempt = session.correction.state.attempt;
    session.correct('close');
    if (session.correction.state.attempt <= attempt) throw new Error('Correction did not advance');
  }
}

export async function stop(session: Session, afterFlush: () => void = () => {}) {
  // Upstream stop returns no final sequence when an issue/retry is open. A
  // terminal SDK Stop explicitly defers it first, preserving its state event.
  // Retry audio is practice, not appended to the original recitation history.
  deferOpenIssues(session);
  await session.stop();
  afterFlush();
  // Publish each queued structural finding before terminal SDK completion.
  // They remain review findings, not actionable errors in a closed run.
  deferOpenIssues(session);
}

export function structuralOptions(value: unknown) {
  return value === 'onStop' || value === 'onPause'
    ? { ayahOrder: 'guarded' as const, similarVerse: true,
      timing: value === 'onPause' ? 'pause' as const : 'stop' as const }
    : false;
}

export class WordEvidencePublisher {
  private revision = 0;
  private signature = '';
  private passage: any = null;
  private prefixKey = '';
  private prefixEvidence: unknown = null;
  constructor(private enabled: boolean, private emit: (event: unknown) => void,
    private corpus?: any) {}
  setExpected(passage: unknown) { this.passage = passage; this.prefixKey = ''; this.prefixEvidence = null; }
  private startingEvidence(transcript: string) {
    if (!this.passage || !this.corpus) return null;
    const table = costTable();
    const stripped = stripPreambles(transcript, table);
    const rest = transcript.slice(stripped.offset);
    if (preamblePending(rest, table) || rest.length < 20) return null;
    // Compare the opening, not a whole take diluted by shared later ayahs.
    const query = rest.slice(0, 32);
    if (this.prefixKey === query) return this.prefixEvidence;
    this.prefixKey = query;
    const {surah,ayah,ayahEnd=ayah}=this.passage;
    const verses = this.corpus.surahs[surah-1].ayahs;
    const q = table.encode(query);
    const fit = (start:number) => {
      let reference = '';
      for (let a=start-1;a<verses.length && reference.length<40;a++) {
        reference += verses[a].w.map((w:any)=>w[1]).join('');
      }
      reference = reference.slice(0,40);
      let distance = Infinity;
      for (let len=Math.max(1,Math.floor(query.length*.8));len<=Math.min(reference.length,Math.ceil(query.length*1.2));len++) {
        distance=Math.min(distance, normalizedDistance(q,table.encode(reference.slice(0,len)),table));
      }
      return distance;
    };
    const expectedDistance=fit(ayah);
    let laterAyah=ayah, laterDistance=Infinity;
    // Bounded adjacent opening comparison, not a second global Quran search.
    for (let a=ayah+1;a<=Math.min(verses.length,ayahEnd,ayah+3);a++) {
      const distance=fit(a);
      if(distance<laterDistance){laterAyah=a;laterDistance=distance;}
    }
    return this.prefixEvidence = Number.isFinite(expectedDistance) && Number.isFinite(laterDistance)
      ? {surah,ayah:laterAyah,expected_distance:expectedDistance,later_distance:laterDistance,phonemes:query.length}
      : null;
  }
  publish(session: Session, audioEnded = false) {
    if (!this.enabled) return;
    const words = session.verdicts().map(v => {
      const copy = { ...v };
      for (const key of ['gop', 'gopNone', 'gopTwice', 'repGain', 'pairGop', 'slip'] as const) {
        if (!Number.isFinite(copy[key])) delete copy[key];
      }
      return copy;
    });
    const data = { attempt: session.correction.state.attempt,
      phoneme_count: session.transcript.length, audio_ended: audioEnded, words,
      start_comparison: this.startingEvidence(session.transcript) };
    // Fresh replacement copies, no union, no made-up stability or timestamps.
    const signature = JSON.stringify(data);
    if (signature === this.signature) return;
    this.signature = signature;
    this.emit({ type: 'word_evidence', revision: ++this.revision, ...data });
  }
  reset() { this.revision = 0; this.signature = ''; this.prefixKey='';this.prefixEvidence=null; }
}
