/**
 * AevumPoseBridge — thin JS adapter between Dart (via @JS interop) and
 * the @mediapipe/tasks-vision PoseLandmarker.
 *
 * Loaded in index.html *before* the Flutter bootstrap script.
 *
 * Usage from Dart:
 *   AevumPoseBridge.initialize()          → Promise<boolean>
 *   AevumPoseBridge.setVideoElement(el)   → void
 *   AevumPoseBridge.processVideoFrame()   → Promise<{landmarks, confidence} | null>
 *   AevumPoseBridge.dispose()             → void
 */
window.AevumPoseBridge = (() => {
  let poseLandmarker = null;
  let videoElement = null;
  let mediaStream = null;
  let lastTimestamp = -1;
  let lastCameraError = null;
  let previewContainer = null;
  let previewLayout = "hidden";
  let previewLayoutListenerBound = false;
  let audioContext = null;
  let masterGain = null;
  let musicGain = null;
  let sfxGain = null;
  let musicLoopTimer = null;
  let musicStarted = false;

  const ALWAYS_USE_FLOATING_PREVIEW = true;
  const FLOATING_PREVIEW_ID = "aevum-floating-camera-preview";

  const WASM_CDN =
    "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/wasm";
  const MODEL_URL =
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task";

  async function ensureAudioContext() {
    const AudioCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtor) return null;

    if (!audioContext) {
      audioContext = new AudioCtor();
      masterGain = audioContext.createGain();
      musicGain = audioContext.createGain();
      sfxGain = audioContext.createGain();

      masterGain.gain.value = 0.8;
      musicGain.gain.value = 0.14;
      sfxGain.gain.value = 0.22;

      musicGain.connect(masterGain);
      sfxGain.connect(masterGain);
      masterGain.connect(audioContext.destination);
    }

    if (audioContext.state === "suspended") {
      await audioContext.resume();
    }

    return audioContext;
  }

  function scheduleTone({ frequency, startTime, duration, volume, type = "sine", target = sfxGain }) {
    if (!audioContext || !target) return;

    const osc = audioContext.createOscillator();
    const gain = audioContext.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(frequency, startTime);

    gain.gain.setValueAtTime(0.0001, startTime);
    gain.gain.exponentialRampToValueAtTime(volume, startTime + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

    osc.connect(gain);
    gain.connect(target);
    osc.start(startTime);
    osc.stop(startTime + duration + 0.02);
  }

  function scheduleMusicLoop(startTime) {
    const melody = [
      { f: 392.0, t: 0.00, d: 0.34 },
      { f: 493.88, t: 0.42, d: 0.26 },
      { f: 587.33, t: 0.82, d: 0.36 },
      { f: 523.25, t: 1.28, d: 0.30 },
      { f: 392.0, t: 1.78, d: 0.34 },
      { f: 440.0, t: 2.18, d: 0.26 },
      { f: 493.88, t: 2.56, d: 0.40 },
      { f: 349.23, t: 3.05, d: 0.46 },
    ];

    const bass = [
      { f: 196.0, t: 0.00, d: 0.70 },
      { f: 220.0, t: 1.55, d: 0.70 },
      { f: 174.61, t: 3.10, d: 0.70 },
    ];

    melody.forEach((note) => {
      scheduleTone({
        frequency: note.f,
        startTime: startTime + note.t,
        duration: note.d,
        volume: 0.045,
        type: "triangle",
        target: musicGain,
      });
    });

    bass.forEach((note) => {
      scheduleTone({
        frequency: note.f,
        startTime: startTime + note.t,
        duration: note.d,
        volume: 0.032,
        type: "sine",
        target: musicGain,
      });
    });
  }

  async function startBackgroundMusic() {
    const ctx = await ensureAudioContext();
    if (!ctx || musicStarted) return false;

    musicStarted = true;
    const loopLength = 4.2;
    const scheduleAhead = () => scheduleMusicLoop(ctx.currentTime + 0.03);
    scheduleAhead();
    musicLoopTimer = window.setInterval(scheduleAhead, loopLength * 1000);
    return true;
  }

  function stopBackgroundMusic() {
    musicStarted = false;
    if (musicLoopTimer) {
      window.clearInterval(musicLoopTimer);
      musicLoopTimer = null;
    }
  }

  async function playScoreSound() {
    const ctx = await ensureAudioContext();
    if (!ctx) return false;
    const now = ctx.currentTime + 0.01;
    scheduleTone({ frequency: 740.0, startTime: now, duration: 0.12, volume: 0.12, type: "triangle" });
    scheduleTone({ frequency: 987.77, startTime: now + 0.07, duration: 0.16, volume: 0.10, type: "sine" });
    return true;
  }

  async function playCountdownSound() {
    const ctx = await ensureAudioContext();
    if (!ctx) return false;
    const now = ctx.currentTime + 0.01;
    scheduleTone({ frequency: 523.25, startTime: now, duration: 0.14, volume: 0.09, type: "triangle" });
    scheduleTone({ frequency: 659.25, startTime: now + 0.1, duration: 0.18, volume: 0.08, type: "triangle" });
    return true;
  }

  async function playDeathSound() {
    const ctx = await ensureAudioContext();
    if (!ctx) return false;
    const now = ctx.currentTime + 0.01;
    scheduleTone({ frequency: 392.0, startTime: now, duration: 0.16, volume: 0.12, type: "sawtooth" });
    scheduleTone({ frequency: 277.18, startTime: now + 0.08, duration: 0.20, volume: 0.11, type: "triangle" });
    scheduleTone({ frequency: 174.61, startTime: now + 0.18, duration: 0.28, volume: 0.10, type: "sine" });
    return true;
  }

  async function playFinishSound() {
    const ctx = await ensureAudioContext();
    if (!ctx) return false;
    const now = ctx.currentTime + 0.01;

    scheduleTone({ frequency: 523.25, startTime: now, duration: 0.12, volume: 0.11, type: "triangle" });
    scheduleTone({ frequency: 659.25, startTime: now + 0.08, duration: 0.12, volume: 0.11, type: "triangle" });
    scheduleTone({ frequency: 783.99, startTime: now + 0.16, duration: 0.14, volume: 0.11, type: "triangle" });
    scheduleTone({ frequency: 1046.5, startTime: now + 0.28, duration: 0.22, volume: 0.13, type: "sine" });
    return true;
  }

  async function initialize() {
    try {
      const vision = await import(
        "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest"
      );

      const { PoseLandmarker, FilesetResolver } = vision;

      const filesetResolver = await FilesetResolver.forVisionTasks(WASM_CDN);

      const createWithDelegate = async (delegate) => {
        return PoseLandmarker.createFromOptions(filesetResolver, {
          baseOptions: {
            modelAssetPath: MODEL_URL,
            delegate,
          },
          runningMode: "VIDEO",
          numPoses: 1,
          minPoseDetectionConfidence: 0.35,
          minPosePresenceConfidence: 0.35,
          minTrackingConfidence: 0.35,
        });
      };

      try {
        poseLandmarker = await createWithDelegate("GPU");
      } catch (gpuError) {
        console.warn("[AevumPoseBridge] GPU delegate unavailable, retrying with CPU", gpuError);
        poseLandmarker = await createWithDelegate("CPU");
      }

      console.log("[AevumPoseBridge] PoseLandmarker initialized");
      return true;
    } catch (e) {
      console.error("[AevumPoseBridge] init error:", e);
      return false;
    }
  }

  function setVideoElement(el) {
    videoElement = el;
  }

  function createVideoElement() {
    const element = document.createElement("video");
    element.autoplay = true;
    element.muted = true;
    element.playsInline = true;
    element.setAttribute("autoplay", "true");
    element.setAttribute("muted", "true");
    element.setAttribute("playsinline", "true");
    element.style.width = "100%";
    element.style.height = "100%";
    element.style.position = "absolute";
    element.style.inset = "0";
    // Show the full camera frame in the preview instead of cropping in.
    element.style.objectFit = "contain";
    element.style.transform = "scaleX(-1)";
    return element;
  }

  function ensureFloatingPreviewContainer() {
    let container = document.getElementById(FLOATING_PREVIEW_ID);
    if (!container) {
      container = document.createElement("div");
      container.id = FLOATING_PREVIEW_ID;
      container.className = "aevum-web-camera-container";
      document.body.appendChild(container);
    }

    container.style.position = "fixed";
    container.style.borderRadius = "16px";
    container.style.overflow = "hidden";
    container.style.background = "#08111b";
    container.style.border = "1px solid rgba(255,255,255,0.24)";
    container.style.boxShadow = "0 8px 20px rgba(0,0,0,0.45)";
    container.style.zIndex = "2147483646";
    container.style.pointerEvents = "none";

    applyPreviewLayout(container);
    ensurePreviewLayoutListener();

    previewContainer = container;
    return container;
  }

  function applyPreviewLayout(container) {
    if (!container) return;

    const viewportWidth = Math.max(
      320,
      Math.round((window.visualViewport && window.visualViewport.width) || window.innerWidth || 0),
    );
    const safeTop = Math.max(
      0,
      (window.visualViewport ? window.visualViewport.offsetTop : 0) || 0,
    );
    const safeRight = Math.max(
      0,
      window.innerWidth -
        (((window.visualViewport && window.visualViewport.offsetLeft) || 0) +
          ((window.visualViewport && window.visualViewport.width) || window.innerWidth)),
    );
    const topPad = `${Math.round(12 + safeTop)}px`;
    const rightPad = `${Math.round(12 + safeRight)}px`;

    if (previewLayout === "hidden") {
      container.style.display = "none";
      return;
    }

    container.style.display = "block";

    if (previewLayout === "center") {
      container.style.left = "50%";
      container.style.top = "50%";
      container.style.right = "auto";
      container.style.bottom = "auto";
      container.style.transform = "translate(-50%, -50%)";
      container.style.width = viewportWidth < 640 ? "min(68vw, 250px)" : "420px";
      container.style.height = viewportWidth < 640 ? "min(46vh, 340px)" : "560px";
      return;
    }

    if (previewLayout === "ready") {
      container.style.left = "50%";
      container.style.top = viewportWidth < 640 ? "30%" : "28%";
      container.style.right = "auto";
      container.style.bottom = "auto";
      container.style.transform = "translate(-50%, -50%)";
      container.style.width = viewportWidth < 640 ? "min(62vw, 230px)" : "360px";
      container.style.height = viewportWidth < 640 ? "min(40vh, 300px)" : "500px";
      return;
    }

    container.style.left = "auto";
    container.style.top = topPad;
    container.style.right = rightPad;
    container.style.bottom = "auto";
    container.style.transform = "none";
    container.style.width = viewportWidth < 640 ? "min(44vw, 176px)" : "300px";
    container.style.height = viewportWidth < 640 ? "min(30vh, 235px)" : "400px";
  }

  function ensurePreviewLayoutListener() {
    if (previewLayoutListenerBound) return;

    const refreshPreviewLayout = () => {
      if (previewContainer) {
        applyPreviewLayout(previewContainer);
      }
    };

    window.addEventListener("resize", refreshPreviewLayout, { passive: true });
    window.addEventListener("orientationchange", refreshPreviewLayout, { passive: true });
    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", refreshPreviewLayout, { passive: true });
      window.visualViewport.addEventListener("scroll", refreshPreviewLayout, { passive: true });
    }

    previewLayoutListenerBound = true;
  }

  function setPreviewLayout(layout) {
    if (layout === "center" || layout === "ready" || layout === "corner" || layout === "hidden") {
      previewLayout = layout;
    } else {
      previewLayout = "hidden";
    }
    if (previewContainer) {
      applyPreviewLayout(previewContainer);
    }
  }

  async function waitForVideoReady(timeoutMs) {
    const start = performance.now();
    while (performance.now() - start < timeoutMs) {
      if (videoElement && videoElement.readyState >= 2 && videoElement.videoWidth > 0 && videoElement.videoHeight > 0) {
        return true;
      }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    return false;
  }

  function getLastCameraError() {
    return lastCameraError;
  }

  function getCameraDebugState() {
    const tracks = mediaStream ? mediaStream.getVideoTracks() : [];
    return JSON.stringify({
      hasVideoElement: !!videoElement,
      inDom: !!(videoElement && videoElement.isConnected),
      usingFloatingPreview: !!(previewContainer && previewContainer.id === FLOATING_PREVIEW_ID),
      previewLayout,
      readyState: videoElement ? videoElement.readyState : -1,
      paused: videoElement ? videoElement.paused : null,
      videoWidth: videoElement ? videoElement.videoWidth : 0,
      videoHeight: videoElement ? videoElement.videoHeight : 0,
      streamActive: mediaStream ? mediaStream.active : false,
      videoTrackCount: tracks.length,
      trackStates: tracks.map((track) => track.readyState),
      lastCameraError,
    });
  }

  async function startCamera(containerId) {
    try {
      lastCameraError = null;
      let container = containerId
        ? document.getElementById(containerId)
        : null;
      if (!container) {
        const candidates = document.querySelectorAll('.aevum-web-camera-container');
        container = candidates.length > 0 ? candidates[candidates.length - 1] : null;
      }
      if (ALWAYS_USE_FLOATING_PREVIEW) {
        container = ensureFloatingPreviewContainer();
      }
      if (!container) {
        lastCameraError = 'no_container';
        return false;
      }
      if (!navigator.mediaDevices?.getUserMedia) {
        lastCameraError = 'unsupported';
        return false;
      }

      if (!videoElement) {
        videoElement = createVideoElement();
      }

      if (videoElement.parentElement && videoElement.parentElement !== container) {
        videoElement.parentElement.removeChild(videoElement);
      }

      container.innerHTML = "";
      container.appendChild(videoElement);

      if (mediaStream && mediaStream.active === false) {
        mediaStream = null;
      }

      if (!mediaStream) {
        const primaryConstraints = {
          video: {
            facingMode: { ideal: "user" },
            width: { ideal: 1280, min: 480 },
            height: { ideal: 720, min: 360 },
          },
          audio: false,
        };
        const fallbackConstraints = {
          video: true,
          audio: false,
        };

        try {
          mediaStream = await navigator.mediaDevices.getUserMedia(primaryConstraints);
        } catch (error) {
          console.warn("[AevumPoseBridge] primary camera constraint failed, retrying with fallback", error);
          mediaStream = await navigator.mediaDevices.getUserMedia(fallbackConstraints);
        }
      }

      const videoTracks = mediaStream ? mediaStream.getVideoTracks() : [];
      if (!videoTracks.length) {
        lastCameraError = 'no_stream_tracks';
        return false;
      }

      if (videoElement.srcObject !== mediaStream) {
        videoElement.srcObject = mediaStream;
      }

      await videoElement.play();

      let ready = await waitForVideoReady(2800);
      if (!ready) {
        console.warn("[AevumPoseBridge] first stream did not produce frames, retrying camera with basic constraints");
        if (mediaStream) {
          for (const track of mediaStream.getTracks()) {
            track.stop();
          }
        }
        mediaStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
        const retryTracks = mediaStream ? mediaStream.getVideoTracks() : [];
        if (!retryTracks.length) {
          lastCameraError = 'no_stream_tracks';
          return false;
        }
        videoElement.srcObject = mediaStream;
        await videoElement.play();
        ready = await waitForVideoReady(2800);
      }

      if (!ready) {
        lastCameraError = 'video_not_ready';
        return false;
      }

      return true;
    } catch (e) {
      if (e && (e.name === 'NotAllowedError' || e.name === 'SecurityError')) {
        lastCameraError = 'permission_denied';
      } else if (e && (e.message === 'video_metadata_timeout' || e.message === 'video_metadata_failed')) {
        lastCameraError = 'video_not_ready';
      } else {
        lastCameraError = 'start_failed';
      }
      console.error("[AevumPoseBridge] camera start error:", e);
      return false;
    }
  }

  async function processVideoFrame() {
    if (!poseLandmarker || !videoElement) return null;
    if (videoElement.readyState < 2) return null; // not enough data

    const now = performance.now();
    if (now === lastTimestamp) return null;
    lastTimestamp = now;

    try {
      const result = poseLandmarker.detectForVideo(videoElement, now);

      if (
        !result ||
        !result.landmarks ||
        result.landmarks.length === 0 ||
        result.landmarks[0].length === 0
      ) {
        return null;
      }

      const lms = result.landmarks[0]; // first person
      const confidence =
        result.worldLandmarks && result.worldLandmarks.length > 0
          ? 0.85
          : 0.5;

      return {
        landmarks: lms.map((lm) => ({
          x: lm.x,
          y: lm.y,
          z: lm.z,
          visibility: lm.visibility ?? 0.0,
        })),
        confidence: confidence,
      };
    } catch (e) {
      console.warn("[AevumPoseBridge] detectForVideo error:", e);
      return null;
    }
  }

  function dispose() {
    if (poseLandmarker) {
      poseLandmarker.close();
      poseLandmarker = null;
    }
    stopCamera();
    lastTimestamp = -1;
  }

  async function stopCamera() {
    if (videoElement) {
      videoElement.pause();
      videoElement.srcObject = null;
      if (videoElement.parentElement) {
        videoElement.parentElement.removeChild(videoElement);
      }
    }
    if (mediaStream) {
      for (const track of mediaStream.getTracks()) {
        track.stop();
      }
      mediaStream = null;
    }
    videoElement = null;
    stopBackgroundMusic();
    if (previewContainer && previewContainer.parentElement) {
      previewContainer.parentElement.removeChild(previewContainer);
    }
    previewContainer = null;
  }

  return {
    initialize,
    setVideoElement,
    getLastCameraError,
    getCameraDebugState,
    setPreviewLayout,
    startBackgroundMusic,
    stopBackgroundMusic,
    playScoreSound,
    playCountdownSound,
    playDeathSound,
    playFinishSound,
    startCamera,
    stopCamera,
    processVideoFrame,
    dispose,
  };
})();
