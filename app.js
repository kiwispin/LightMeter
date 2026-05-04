const video = document.querySelector("#camera");
const canvas = document.querySelector("#sampler");
const kelvinEl = document.querySelector("#kelvin");
const tintEl = document.querySelector("#tint");
const rgbEl = document.querySelector("#rgb");
const levelEl = document.querySelector("#level");
const messageEl = document.querySelector("#message");
const startButton = document.querySelector("#startButton");
const holdButton = document.querySelector("#holdButton");
const torchButton = document.querySelector("#torchButton");

const ctx = canvas.getContext("2d", { willReadFrequently: true });

let stream;
let videoTrack;
let animationFrame;
let isHeld = false;
let torchOn = false;
let smoothKelvin = 0;
let smoothTint = 0;
let smoothLight = 0;

startButton.addEventListener("click", startCamera);
holdButton.addEventListener("click", toggleHold);
torchButton.addEventListener("click", toggleTorch);

window.addEventListener("pagehide", stopCamera);

async function startCamera() {
  if (!navigator.mediaDevices?.getUserMedia) {
    setMessage("Camera access is not available in this browser.");
    return;
  }

  startButton.disabled = true;
  startButton.textContent = "Starting...";

  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: { ideal: "environment" },
        width: { ideal: 1920 },
        height: { ideal: 1080 },
        frameRate: { ideal: 30, max: 60 },
      },
      audio: false,
    });

    video.srcObject = stream;
    videoTrack = stream.getVideoTracks()[0];
    await video.play();

    configureTorchButton();
    holdButton.disabled = false;
    startButton.textContent = "Camera on";
    setMessage("Metering from the center target.");
    sampleLoop();
  } catch (error) {
    startButton.disabled = false;
    startButton.textContent = "Start camera";
    setMessage(readableCameraError(error));
  }
}

function stopCamera() {
  cancelAnimationFrame(animationFrame);
  stream?.getTracks().forEach((track) => track.stop());
}

function sampleLoop() {
  if (!isHeld && video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
    const reading = readCenterPatch();

    if (reading) {
      updateReading(reading);
    }
  }

  animationFrame = requestAnimationFrame(sampleLoop);
}

function readCenterPatch() {
  const sourceWidth = video.videoWidth;
  const sourceHeight = video.videoHeight;

  if (!sourceWidth || !sourceHeight) {
    return null;
  }

  const patchSize = Math.round(Math.min(sourceWidth, sourceHeight) * 0.16);
  const sx = Math.round((sourceWidth - patchSize) / 2);
  const sy = Math.round((sourceHeight - patchSize) / 2);

  ctx.drawImage(video, sx, sy, patchSize, patchSize, 0, 0, canvas.width, canvas.height);

  const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
  const average = averageBalancedPixels(pixels);

  if (!average) {
    return null;
  }

  const kelvin = rgbToKelvin(average.r, average.g, average.b);
  const tint = tintFromRgb(average.r, average.g, average.b);
  const light = relativeLightLevel(average.r, average.g, average.b);

  return { ...average, kelvin, tint, light };
}

function averageBalancedPixels(pixels) {
  const buckets = [];

  for (let index = 0; index < pixels.length; index += 4) {
    const r = pixels[index];
    const g = pixels[index + 1];
    const b = pixels[index + 2];
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;

    if (luminance < 24 || luminance > 242 || max - min > 115) {
      continue;
    }

    buckets.push({ r, g, b, luminance });
  }

  if (buckets.length < pixels.length / 16) {
    return null;
  }

  buckets.sort((a, b) => a.luminance - b.luminance);
  const start = Math.floor(buckets.length * 0.12);
  const end = Math.ceil(buckets.length * 0.88);
  const trimmed = buckets.slice(start, end);

  const total = trimmed.reduce(
    (sum, pixel) => ({
      r: sum.r + pixel.r,
      g: sum.g + pixel.g,
      b: sum.b + pixel.b,
    }),
    { r: 0, g: 0, b: 0 },
  );

  return {
    r: total.r / trimmed.length,
    g: total.g / trimmed.length,
    b: total.b / trimmed.length,
  };
}

function updateReading(reading) {
  smoothKelvin = smoothKelvin ? smooth(smoothKelvin, reading.kelvin, 0.16) : reading.kelvin;
  smoothTint = smooth(smoothTint, reading.tint, 0.18);
  smoothLight = smoothLight ? smooth(smoothLight, reading.light, 0.18) : reading.light;

  kelvinEl.textContent = `${roundTo(smoothKelvin, 50)} K`;
  tintEl.textContent = formatTint(smoothTint);
  rgbEl.textContent = `${Math.round(reading.r)} ${Math.round(reading.g)} ${Math.round(reading.b)}`;
  levelEl.textContent = `${Math.round(smoothLight)}%`;
}

function rgbToKelvin(r, g, b) {
  const [linearR, linearG, linearB] = [r, g, b].map(srgbToLinear);

  const xValue = linearR * 0.4124564 + linearG * 0.3575761 + linearB * 0.1804375;
  const yValue = linearR * 0.2126729 + linearG * 0.7151522 + linearB * 0.072175;
  const zValue = linearR * 0.0193339 + linearG * 0.119192 + linearB * 0.9503041;
  const total = xValue + yValue + zValue;

  if (!total) {
    return 0;
  }

  const x = xValue / total;
  const y = yValue / total;
  const n = (x - 0.332) / (0.1858 - y);
  const cct = 449 * n ** 3 + 3525 * n ** 2 + 6823.3 * n + 5520.33;

  return clamp(cct, 1000, 40000);
}

function srgbToLinear(value) {
  const channel = value / 255;
  return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
}

function tintFromRgb(r, g, b) {
  const magentaGreen = (r + b) / 2 - g;
  return clamp((magentaGreen / 128) * 100, -100, 100);
}

function relativeLightLevel(r, g, b) {
  return clamp(((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255) * 100, 0, 100);
}

function formatTint(tint) {
  if (Math.abs(tint) < 4) {
    return "Neutral";
  }

  return tint > 0 ? `+${Math.round(tint)} M` : `${Math.round(Math.abs(tint))} G`;
}

function smooth(current, next, amount) {
  return current + (next - current) * amount;
}

function roundTo(value, nearest) {
  return Math.round(value / nearest) * nearest;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function toggleHold() {
  isHeld = !isHeld;
  holdButton.textContent = isHeld ? "Live" : "Hold";
  setMessage(isHeld ? "Reading held." : "Metering from the center target.");
}

async function toggleTorch() {
  if (!videoTrack) {
    return;
  }

  try {
    torchOn = !torchOn;
    await videoTrack.applyConstraints({ advanced: [{ torch: torchOn }] });
    torchButton.classList.toggle("is-active", torchOn);
  } catch {
    torchOn = false;
    setMessage("Torch control is not available on this camera.");
  }
}

function configureTorchButton() {
  const capabilities = videoTrack?.getCapabilities?.();
  const hasTorch = Boolean(capabilities?.torch);
  torchButton.hidden = !hasTorch;
}

function setMessage(message) {
  messageEl.textContent = message;
}

function readableCameraError(error) {
  if (location.protocol !== "https:" && location.hostname !== "localhost") {
    return "Camera access needs HTTPS. GitHub Pages will handle that.";
  }

  if (error?.name === "NotAllowedError") {
    return "Camera permission was blocked.";
  }

  if (error?.name === "NotFoundError") {
    return "No camera was found.";
  }

  return "Camera could not be started.";
}
