# Kelvin Meter

A static browser light-meter page for estimating correlated color temperature from a phone camera.

## Use

Open the page over HTTPS, start the camera, and point the center target at a white or neutral grey card in the light you want to measure. The displayed kelvin value is an estimate intended for filming decisions.

Phone browsers and camera hardware often apply automatic white balance and image processing before JavaScript receives the pixels, so readings should be treated as a practical guide rather than a calibrated measurement.

## Publish With GitHub Pages

This project is intentionally dependency-free. It can be published from the repository root with GitHub Pages.

1. Push the files to a GitHub repository.
2. In GitHub, open **Settings > Pages**.
3. Set **Source** to **Deploy from a branch**.
4. Choose the `main` branch and `/ (root)` folder.

Camera access requires HTTPS on phones. GitHub Pages provides HTTPS automatically.
