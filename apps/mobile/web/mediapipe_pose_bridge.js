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
  let lastTimestamp = -1;

  const WASM_CDN =
    "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/wasm";
  const MODEL_URL =
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task";

  async function initialize() {
    try {
      const vision = await import(
        "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest"
      );

      const { PoseLandmarker, FilesetResolver } = vision;

      const filesetResolver = await FilesetResolver.forVisionTasks(WASM_CDN);

      poseLandmarker = await PoseLandmarker.createFromOptions(filesetResolver, {
        baseOptions: {
          modelAssetPath: MODEL_URL,
          delegate: "GPU",
        },
        runningMode: "VIDEO",
        numPoses: 1,
        minPoseDetectionConfidence: 0.5,
        minPosePresenceConfidence: 0.5,
        minTrackingConfidence: 0.5,
      });

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
    videoElement = null;
  }

  return { initialize, setVideoElement, processVideoFrame, dispose };
})();
