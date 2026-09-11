# Third-party notices

## Vosk API

HOMI's optional Android offline English and Vietnamese recognition uses Vosk API by Alpha Cephei Inc.

- Project: https://github.com/alphacep/vosk-api
- Android library: `com.alphacephei:vosk-android:0.3.75`
- License: Apache License 2.0

## Vosk small US English model

The optional model `vosk-model-small-en-us-0.15` is downloaded only after parent approval.

- Source: https://alphacephei.com/vosk/models
- Archive SHA-256: `30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498`
- License: Apache License 2.0

## Vosk small Vietnamese model

The optional model `vosk-model-small-vn-0.4` is downloaded only after parent approval.

- Source: https://alphacephei.com/vosk/models
- Archive SHA-256: `efe5c8494212110471a79befc48c79da679e5b1fc52a4ffb500222ff86d622e5`
- License: Apache License 2.0

## Google ML Kit on-device translation

HOMI optionally downloads the Vietnamese and English ML Kit language models after parent approval and uses them to translate text on the device when the production backend is unavailable.

- Product documentation: https://developers.google.com/ml-kit/language/translation
- Usage and attribution terms: https://developers.google.com/ml-kit/language/translation/translation-terms
- Flutter integration: `google_mlkit_translation: 0.15.1`
- Flutter integration license: MIT

Translations are generated automatically using translation software powered by Google Translate. Automatic translations may be inaccurate. Google disclaims warranties related to these translations, including warranties of accuracy, reliability, merchantability, fitness for a particular purpose, and noninfringement.

## Java Native Access (JNA)

Vosk's Android artifact depends on Java Native Access.

- Project: https://github.com/java-native-access/jna
- License: Apache License 2.0 or LGPL 2.1+
