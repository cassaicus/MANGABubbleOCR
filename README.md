# MANGABubbleOCR

**MANGABubbleOCR** is a macOS manga viewer that automatically detects speech bubbles in images, performs OCR to extract the text, translates it, and overlays the translated text directly onto the original bubble positions — creating a seamless translated reading experience.

## ✨ Features

- **Automatic Speech Bubble Detection**  
  Uses a CoreML model trained with **YORO** to locate speech bubbles in manga images.

- **OCR (Optical Character Recognition)**  
  Integrates a CoreML‑converted version of **MANGA-OCR** to recognize Japanese text from detected bubbles.

- **Instant Translation**  
  Utilizes `TranslationSession` to translate Japanese text into English in real time.

- **Overlay Rendering**  
  Places translated text back into the original bubble positions for a natural reading flow.

- **macOS 26+ Required**  
  Built with the latest macOS APIs and features.

## 📦 Requirements

- macOS 26 or later
- Apple Silicon or Intel Mac
- Internet connection for translation

## 🚀 Getting Started

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/MANGABubbleOCR.git


## 📄 License Notes

This project uses the following third-party components:

- **MANGA-OCR**  
  Licensed under the Apache License 2.0.  
  © kha-white.  
  See: https://github.com/kha-white/manga-ocr  
  You must include the original copyright notice and license text when redistributing.

- **YORO**  
  Licensed under the GNU General Public License v3.0 (GPL-3.0).  
  See: https://github.com/YORO-VR/YORO-VR  
  Any derivative work or redistribution must also be licensed under GPL-3.0, and source code must be made available.

Please ensure compliance with each license when modifying or distributing this application.
