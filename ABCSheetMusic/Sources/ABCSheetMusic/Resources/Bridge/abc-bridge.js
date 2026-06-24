/* abcjs bridge — called from Swift via WKWebView.evaluateJavaScript */
(function () {
  "use strict";

  if (typeof ABCJS === "undefined") {
    window.__abcBridgeReady = false;
    window.__abcBridgeError = "abcjs failed to load";
    return;
  }

  let synthControl = null;
  let lastVisualObj = null;

  function CursorControl() {
    this.beatSubdivisions = 2;
    this.onEvent = function (ev) {
      if (ev.measureStart && ev.left === null) return;
      document.querySelectorAll("#paper svg .highlight").forEach(function (el) {
        el.classList.remove("highlight");
      });
      ev.elements.forEach(function (g) {
        g.forEach(function (el) { el.classList.add("highlight"); });
      });
    };
    this.onFinished = function () {
      document.querySelectorAll("#paper svg .highlight").forEach(function (el) {
        el.classList.remove("highlight");
      });
      postMessage({ type: "playbackFinished" });
    };
  }

  function initSynth() {
    if (!ABCJS.synth.supportsAudio()) return;
    synthControl = new ABCJS.synth.SynthController();
    synthControl.load("#audio", new CursorControl(), {
      displayPlay: false,
      displayRestart: false,
      displayProgress: false,
      displayWarp: false,
    });
  }

  function renderParams(measuresPerLine) {
    return {
      responsive: "resize",
      oneSvgPerLine: true,
      add_classes: true,
      staffwidth: 840,
      paddingleft: 20,
      paddingright: 20,
      paddingtop: 16,
      paddingbottom: 10,
      stretchlast: 0.04,
      flatbeams: false,
      wrap: {
        preferredMeasuresPerLine: measuresPerLine || 1,
        minSpacing: 1.35,
        maxSpacing: 2.3,
        lastLineLimit: 2,
      },
    };
  }

  function meterWarnings(abc) {
    var tune = ABCJS.parseOnly(abc)[0];
    var msgs = [];
    var bar = 0;
    tune.lines.forEach(function (line) {
      (line.staff || []).forEach(function (staff) {
        (staff.voices || []).forEach(function (voice) {
          var dur = 0;
          voice.forEach(function (el) {
            if (typeof el.duration === "number" && el.el_type !== "bar") dur += el.duration;
            if (el.el_type === "bar") {
              bar++;
              if (dur > 0 && Math.abs(dur - 1) > 0.02) {
                msgs.push("Bar " + bar + ": " + (dur * 4).toFixed(2) + " beats (expected 4.00)");
              }
              dur = 0;
            }
          });
        });
      });
    });
    return msgs;
  }

  window.ABCBridge = {
    signature: ABCJS.signature || "abcjs",

    transpose: function (abc, steps) {
      steps = parseInt(steps, 10) || 0;
      if (!steps) return abc;
      return ABCJS.strTranspose(abc, ABCJS.parseOnly(abc), steps);
    },

    render: function (abc, measuresPerLine) {
      var warnings = [];
      try {
        ABCJS.parseOnly(abc);
        warnings = warnings.concat(meterWarnings(abc));
        var objs = ABCJS.renderAbc("paper", abc, renderParams(measuresPerLine));
        lastVisualObj = objs[0] || null;
        objs.forEach(function (o, i) {
          (o.warnings || []).forEach(function (w) {
            warnings.push("Tune " + (i + 1) + ": " + w.message);
          });
        });
        return { ok: true, warnings: warnings, hasVisual: !!lastVisualObj };
      } catch (e) {
        return { ok: false, warnings: [String(e.message || e)], hasVisual: false };
      }
    },

    loadSynth: function (midiTranspose, program) {
      if (!synthControl || !lastVisualObj) return Promise.resolve({ ok: false });
      synthControl.disable(true);
      var opts = { midiTranspose: midiTranspose || 0, program: program || 0 };
      return new ABCJS.synth.CreateSynth()
        .init({ visualObj: lastVisualObj, options: opts })
        .then(function () { return synthControl.setTune(lastVisualObj, false, opts); })
        .then(function () { synthControl.disable(false); return { ok: true }; })
        .catch(function (e) { return { ok: false, error: String(e) }; });
    },

    play: function () {
      if (!synthControl) return Promise.resolve({ ok: false });
      if (ABCJS.synth.registerAudioContext) {
        return ABCJS.synth.registerAudioContext().then(function () {
          return synthControl.play();
        }).then(function () { return { ok: true }; })
          .catch(function (e) { return { ok: false, error: String(e) }; });
      }
      return synthControl.play().then(function () { return { ok: true }; });
    },

    stop: function () {
      if (synthControl) synthControl.pause();
    },
  };

  initSynth();
  window.__abcBridgeReady = true;
  window.__abcBridgeError = null;

  function postMessage(payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
      window.webkit.messageHandlers.bridge.postMessage(payload);
    }
  }
  postMessage({ type: "ready", signature: ABCJS.signature });
})();