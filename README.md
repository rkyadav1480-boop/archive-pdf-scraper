# 📚 Internet Archive PDF Scraper — Flutter App

Python script ka Flutter version. Bina Flutter install kiye APK banayein!

---

## 🚀 GitHub se APK kaise lein (Mobile-Friendly Guide)

### Step 1 — GitHub par repo banayein
1. [github.com](https://github.com) par jaayein → **New repository**
2. Name: `archive-pdf-scraper`
3. Public rakho → **Create repository**

### Step 2 — Yeh files upload karein
Ye saari files apne repo mein daalo (structure same rakho):
```
archive-pdf-scraper/
├── lib/
│   └── main.dart
├── android/
│   └── app/
│       └── src/
│           └── main/
│               └── AndroidManifest.xml
├── .github/
│   └── workflows/
│       └── build.yml
└── pubspec.yaml
```

### Step 3 — APK automatically build hoga
- Jab bhi aap `main` branch pe push karoge, GitHub Actions automatically APK build karega
- Build 5-10 minute leta hai

### Step 4 — APK download karein
1. Repo mein **Actions** tab pe click karo
2. Latest green ✅ run pe click karo
3. Neeche **Artifacts** section mein `Archive-PDF-Scraper-APK` milega
4. Download karo → unzip karo → APK install karo

---

## 📱 App Features

| Feature | Description |
|---------|-------------|
| 🌐 Language filter | Hindi, English, Urdu, Bengali, Tamil, Telugu, Marathi, Gujarati, Punjabi, Sanskrit |
| 📂 Category filter | 15 categories (novel, science, history, etc.) |
| 🔤 Keyword search | Title / Author / Topic se search |
| 📄 PDF list | Har book ke saare PDF files dikhata hai |
| 💾 Download | Progress bar ke saath SD card mein save |
| ⏭️ Resume support | Already downloaded files skip hoti hain |
| 🔗 Links log | Saved/Downloaded links ka history |
| 📖 PDF open | Seedha app se PDF kholein |
| 📄 Pagination | Agle page ke results bhi dekho |

---

## ⚠️ Android Installation

APK install karne ke liye:
1. Settings → Security → **Unknown sources** ON karein
2. Ya Settings → Apps → Special app access → **Install unknown apps**

---

## 🛠️ Local development (agar Flutter install karna ho)

```bash
flutter pub get
flutter run          # debug mode
flutter build apk --release
```
