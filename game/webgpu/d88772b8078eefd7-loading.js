// The boot readout: what the browser is doing during the minute before the client can draw.
//
// A wasm bundle this size is a long silent stare at a black page, and silence reads as broken --
// the same fault the deck's loading veil exists to end, one layer earlier and with nothing of the
// client running yet to say so. Trunk's `data-initializer` hook (index.html) is what makes this
// possible: it hands over the fetch of the wasm and reports bytes as they land.
//
// THE TOTAL IS THE BUILD'S OWN FIGURE, not a header. Trunk bakes the built bundle's true byte
// count into its loader shim and passes it as the progress `total`, while `current` counts bytes
// after decoding -- so the percentage stays honest behind brotli, where `Content-Length` is the
// COMPRESSED size and would have the bar reach 100% about a fifth of the way in.
//
// Two phases, because they fail differently and a pilot should be able to tell them apart: the
// DOWNLOAD, which is bytes and can be reported exactly, and the COMPILE the browser does once the
// bytes are in, which reports nothing at all and is several seconds of a pinned core. A bar that
// sat full and still through the second one would read as a hang.

/// How many megabytes, at one decimal below ten and whole numbers above -- 8.4 MB reads as
/// progress, 178.3 MB reads as noise.
function mb(bytes) {
  const m = bytes / (1024 * 1024);
  return m < 10 ? `${m.toFixed(1)} MB` : `${Math.round(m)} MB`;
}

export default function () {
  const el = (id) => document.getElementById(id);
  const bar = () => el('boot-bar');
  const note = () => el('boot-note');
  const box = () => el('boot');

  const say = (text) => {
    const n = note();
    if (n) n.textContent = text;
  };

  const fill = (fraction) => {
    const b = bar();
    if (b) b.style.width = `${Math.max(0, Math.min(1, fraction)) * 100}%`;
  };

  return {
    onStart: () => {
      say('powering up...');
    },
    onProgress: ({ current, total }) => {
      // A build served without its size (or any future trunk that stops passing one) still gets
      // an honest line: bytes so far, and a bar that stays where it is rather than lying.
      if (!total || !isFinite(total)) {
        say(`powering up... ${mb(current)}`);
        return;
      }
      fill(current / total);
      say(`powering up... ${mb(current)} of ${mb(total)}`);
    },
    onComplete: () => {
      // The bytes are in and the browser is compiling them. Named, because it is the part with
      // no progress to report and the part a pilot would otherwise read as the bar sticking.
      fill(1);
      say('starting the client...');
    },
    onSuccess: () => {
      const b = box();
      if (!b) return;
      // Fade rather than cut: bevy's first frames are the login screen arriving under this, and
      // a hard swap makes a settled page look like a flash of something going wrong.
      b.style.opacity = '0';
      setTimeout(() => b.remove(), 400);
    },
    onFailure: (error) => {
      fill(1);
      const b = bar();
      if (b) b.style.background = '#8a5340';
      say('The client failed to load. Reload the page to try again.');
      // The detail goes to the console, where a bug report can find it, and never into the line
      // above -- a wasm fetch error is a paragraph of URL and status nobody can act on.
      console.error('client load failed:', error);
    },
  };
}
