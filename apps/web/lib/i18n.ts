// Screen words in the languages field staff use. Field labels come from the module definitions.
export const LANGS = { en: "English", te: "తెలుగు", hi: "हिन्दी", ta: "தமிழ்", kn: "ಕನ್ನಡ" } as const;
export type Lang = keyof typeof LANGS;

const T: Record<string, Partial<Record<Lang, string>>> = {
  home: { te: "హోమ్", hi: "होम", ta: "முகப்பு", kn: "ಮುಖಪುಟ" },
  approvals: { te: "ఆమోదాలు", hi: "मंज़ूरी", ta: "ஒப்புதல்கள்", kn: "ಅನುಮೋದನೆಗಳು" },
  dashboard: { te: "డ్యాష్‌బోర్డ్", hi: "डैशबोर्ड", ta: "டாஷ்போர்டு", kn: "ಡ್ಯಾಶ್‌ಬೋರ್ಡ್" },
  reports: { te: "నివేదికలు", hi: "रिपोर्ट", ta: "அறிக்கைகள்", kn: "ವರದಿಗಳು" },
  admin: { te: "అడ్మిన్", hi: "एडमिन", ta: "நிர்வாகம்", kn: "ಆಡ್ಮಿನ್" },
  assistant: { te: "సహాయకుడు", hi: "सहायक", ta: "உதவியாளர்", kn: "ಸಹಾಯಕ" },
  new: { te: "కొత్తది", hi: "नया", ta: "புதியது", kn: "ಹೊಸದು" },
  save: { te: "సేవ్", hi: "सेव करें", ta: "சேமி", kn: "ಉಳಿಸಿ" },
  submit: { te: "పంపండి", hi: "भेजें", ta: "சமர்ப்பி", kn: "ಸಲ್ಲಿಸಿ" },
  cancel_doc: { te: "రద్దు", hi: "रद्द करें", ta: "ரத்து", kn: "ರದ್ದು" },
  approve: { te: "ఆమోదించు", hi: "मंज़ूर", ta: "ஒப்புதல்", kn: "ಅನುಮೋದಿಸಿ" },
  reject: { te: "తిరస్కరించు", hi: "अस्वीकार", ta: "நிராகரி", kn: "ತಿರಸ್ಕರಿಸಿ" },
  search: { te: "వెతకండి", hi: "खोजें", ta: "தேடு", kn: "ಹುಡುಕಿ" },
  all_fields: { te: "అన్ని వివరాలు", hi: "सभी जानकारी", ta: "அனைத்து விவரங்கள்", kn: "ಎಲ್ಲಾ ವಿವರಗಳು" },
  fewer_fields: { te: "తక్కువ వివరాలు", hi: "कम जानकारी", ta: "குறைவான விவரங்கள்", kn: "ಕಡಿಮೆ ವಿವರಗಳು" },
  history: { te: "చరిత్ర", hi: "इतिहास", ta: "வரலாறு", kn: "ಇತಿಹಾಸ" },
  offline: { te: "ఇంటర్నెట్ లేదు — సేవ్ అవుతుంది", hi: "नेट नहीं — सेव हो जाएगा", ta: "இணையம் இல்லை — சேமிக்கப்படும்", kn: "ಇಂಟರ್ನೆಟ್ ಇಲ್ಲ — ಉಳಿಸಲಾಗುತ್ತದೆ" },
  waiting: { te: "పంపడానికి వేచి ఉన్నాయి", hi: "भेजने के लिए बाकी", ta: "அனுப்ப காத்திருக்கிறது", kn: "ಕಳುಹಿಸಲು ಬಾಕಿ" },
  saved: { te: "సేవ్ అయింది", hi: "सेव हो गया", ta: "சேமிக்கப்பட்டது", kn: "ಉಳಿಸಲಾಗಿದೆ" },
  saved_offline: { te: "ఫోన్‌లో సేవ్ అయింది, నెట్ వచ్చాక పంపుతాం", hi: "फ़ोन में सेव, नेट आने पर भेजेंगे", ta: "போனில் சேமிக்கப்பட்டது, இணையம் வந்ததும் அனுப்பப்படும்", kn: "ಫೋನ್‌ನಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ, ನೆಟ್ ಬಂದಾಗ ಕಳುಹಿಸಲಾಗುತ್ತದೆ" },
  not_enabled: { te: "ఈ విభాగం మీకు అందుబాటులో లేదు", hi: "यह मॉड्यूल आपके लिए चालू नहीं है", ta: "இந்த பகுதி உங்களுக்கு இயக்கப்படவில்லை", kn: "ಈ ವಿಭಾಗ ನಿಮಗೆ ಲಭ್ಯವಿಲ್ಲ" },
  nothing_yet: { te: "ఇంకా ఏమీ లేదు", hi: "अभी कुछ नहीं", ta: "இன்னும் எதுவும் இல்லை", kn: "ಇನ್ನೂ ಏನೂ ಇಲ್ಲ" },
  sign_out: { te: "లాగ్ అవుట్", hi: "लॉग आउट", ta: "வெளியேறு", kn: "ಲಾಗ್ ಔಟ್" },
  location: { te: "ప్రదేశం", hi: "जगह", ta: "இடம்", kn: "ಸ್ಥಳ" },
  company: { te: "కంపెనీ", hi: "कंपनी", ta: "நிறுவனம்", kn: "ಕಂಪನಿ" },
  today_jobs: { te: "ఈ రోజు పనులు", hi: "आज के काम", ta: "இன்றைய வேலைகள்", kn: "ಇಂದಿನ ಕೆಲಸಗಳು" },
  more: { te: "ఇంకా", hi: "और", ta: "மேலும்", kn: "ಇನ್ನಷ್ಟು" },
  reason: { te: "కారణం", hi: "कारण", ta: "காரணம்", kn: "ಕಾರಣ" },
  take_photo: { te: "ఫోటో తీయండి", hi: "फ़ोटो लें", ta: "புகைப்படம் எடு", kn: "ಫೋಟೋ ತೆಗೆಯಿರಿ" },
  speak: { te: "మాట్లాడండి", hi: "बोलिए", ta: "பேசுங்கள்", kn: "ಮಾತನಾಡಿ" },
  add_line: { te: "లైన్ జోడించు", hi: "लाइन जोड़ें", ta: "வரி சேர்", kn: "ಸಾಲು ಸೇರಿಸಿ" },
  next: { te: "తరువాత", hi: "आगे", ta: "அடுத்து", kn: "ಮುಂದೆ" },
  check_and_save: { te: "ఒకసారి చూసి సేవ్ చేయండి", hi: "एक बार देखकर सेव करें", ta: "சரிபார்த்து சேமிக்கவும்", kn: "ಪರಿಶೀಲಿಸಿ ಉಳಿಸಿ" },
  full_form: { te: "పూర్తి ఫారం చూపించు", hi: "पूरा फॉर्म दिखाएं", ta: "முழு படிவம்", kn: "ಪೂರ್ಣ ಫಾರ್ಮ್" },
  step_by_step: { te: "ఒక్కొక్కటిగా", hi: "एक-एक करके", ta: "படிப்படியாக", kn: "ಹಂತ ಹಂತವಾಗಿ" },
  continue: { te: "కొనసాగించు", hi: "जारी रखें", ta: "தொடரவும்", kn: "ಮುಂದುವರಿಸಿ" },
  voice_on: { te: "మాట వినిపించు", hi: "आवाज़ चालू", ta: "குரல் இயக்கு", kn: "ಧ್ವನಿ ಆನ್" },
};

const EN: Record<string, string> = {
  home: "Home", approvals: "Approvals", dashboard: "Dashboard", reports: "Reports", admin: "Admin", assistant: "Assistant",
  new: "New", save: "Save", submit: "Submit", cancel_doc: "Cancel", approve: "Approve", reject: "Reject", search: "Search",
  all_fields: "Show all fields", fewer_fields: "Show fewer fields", history: "History",
  offline: "No signal — entries are saved on this phone", waiting: "waiting to send", saved: "Saved",
  saved_offline: "Saved on this phone. It will be sent when the signal is back.",
  not_enabled: "This module is not enabled for your company or your account.", nothing_yet: "Nothing here yet",
  sign_out: "Sign out", location: "Location", company: "Company", today_jobs: "Today's work", more: "More",
  reason: "Reason", take_photo: "Take photo", speak: "Speak", add_line: "Add line",
  next: "Next", check_and_save: "Check and save", full_form: "Show the full form", step_by_step: "Step by step",
  continue: "Continue", voice_on: "Read aloud",
};

export function t(key: string, lang: Lang): string {
  return T[key]?.[lang] ?? EN[key] ?? key;
}
