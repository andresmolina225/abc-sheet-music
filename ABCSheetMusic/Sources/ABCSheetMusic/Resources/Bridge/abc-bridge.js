/* abcjs bridge — Swift calls via WKWebView.evaluateJavaScript (serialized) */
(function () {
  "use strict";

  function postMessage(payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
        window.webkit.messageHandlers.bridge.postMessage(payload);
      }
    } catch (e) { /* ignore */ }
  }

  window.onerror = function (msg, url, line) {
    postMessage({ type: "jsError", message: String(msg), line: line || 0 });
    return false;
  };

  if (typeof ABCJS === "undefined") {
    postMessage({ type: "error", message: "abcjs failed to load — check bundle paths" });
    return;
  }

  var synthControl = null;
  var lastVisualObj = null;
  var synthReady = false;
  var audioSupported = ABCJS.synth.supportsAudio();

  function CursorControl() {
    this.beatSubdivisions = 2;
    this.onEvent = function (ev) {
      if (ev.measureStart && ev.left === null) return;
      document.querySelectorAll("#paper svg .highlight").forEach(function (el) {
        el.classList.remove("highlight");
      });
      (ev.elements || []).forEach(function (g) {
        (g || []).forEach(function (el) { el.classList.add("highlight"); });
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
    if (!audioSupported) {
      postMessage({ type: "log", message: "Web Audio not supported in this WebView" });
      return;
    }
    try {
      synthControl = new ABCJS.synth.SynthController();
      synthControl.load("#audio", new CursorControl(), {
        displayPlay: false,
        displayRestart: false,
        displayProgress: false,
        displayWarp: false,
      });
    } catch (e) {
      postMessage({ type: "error", message: "Synth init failed: " + e });
    }
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
    var msgs = [];
    try {
      var tune = ABCJS.parseOnly(abc)[0];
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
    } catch (e) {
      msgs.push("Meter check: " + e);
    }
    return msgs;
  }

  /** registerAudioContext() returns boolean; only AudioContext.resume() is a Promise. */
  function resumeAudioContext() {
    try {
      if (ABCJS.synth.registerAudioContext) ABCJS.synth.registerAudioContext();
    } catch (e) { /* ignore */ }
    var ac = window.abcjsAudioContext;
    if (!ac || typeof ac.resume !== "function") return Promise.resolve();
    try {
      var p = ac.resume();
      return (p && typeof p.then === "function") ? p : Promise.resolve();
    } catch (e) {
      return Promise.resolve();
    }
  }

  window.ABCBridge = {
    signature: ABCJS.signature || "abcjs",
    audioSupported: audioSupported,

    ping: function () {
      return { ok: true, signature: ABCJS.signature, audioSupported: audioSupported };
    },

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
        synthReady = false;
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
      if (!audioSupported) {
        return Promise.resolve({ ok: false, error: "Web Audio unavailable" });
      }
      if (!synthControl) {
        return Promise.resolve({ ok: false, error: "Synth controller not initialized" });
      }
      if (!lastVisualObj) {
        return Promise.resolve({ ok: false, error: "Nothing rendered yet — click Render" });
      }
      synthReady = false;
      synthControl.disable(true);
      var opts = { midiTranspose: midiTranspose || 0, program: program || 0 };
      return resumeAudioContext()
        .then(function () {
          return new ABCJS.synth.CreateSynth().init({ visualObj: lastVisualObj, options: opts });
        })
        .then(function () {
          return synthControl.setTune(lastVisualObj, false, opts);
        })
        .then(function () {
          synthControl.disable(false);
          synthReady = true;
          return { ok: true };
        })
        .catch(function (e) {
          synthReady = false;
          return { ok: false, error: String(e && e.message ? e.message : e) };
        });
    },

    play: function () {
      if (!audioSupported) {
        return Promise.resolve({ ok: false, error: "Web Audio unavailable" });
      }
      if (!synthControl || !lastVisualObj) {
        return Promise.resolve({ ok: false, error: "Render first, then Play" });
      }
      return resumeAudioContext()
        .then(function () {
          if (!synthReady) {
            return Promise.resolve({ ok: false, error: "Synth not loaded — wait for render" });
          }
          return synthControl.play();
        })
        .then(function (result) {
          if (result && result.status === "loading") {
            return { ok: false, error: "Synth still loading soundfont (needs network)" };
          }
          return { ok: true };
        })
        .catch(function (e) {
          return { ok: false, error: String(e && e.message ? e.message : e) };
        });
    },

    stop: function () {
      if (synthControl) synthControl.pause();
      return { ok: true };
    },
  };

  initSynth();
  postMessage({ type: "ready", signature: ABCJS.signature, audioSupported: audioSupported });
})();