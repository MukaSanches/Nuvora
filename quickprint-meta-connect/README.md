# Quick Print Meta Connect

Ponte pública e sem estado para o WhatsApp Embedded Signup do Quick Print OS.

- Não persiste Meta App Secret.
- Não persiste access token.
- Usa sessão HMAC curta e ticket AES-GCM curto.
- Suporta authorization code ou business token.
- Resolve WABA/Phone Number ID quando possível.
- Graph API v26.0.

O Android mantém App Secret e access token em armazenamento protegido pelo Android Keystore.
