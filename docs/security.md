# Security Rules

This repository is public. Never commit:

- production or test credentials;
- backend source archives;
- APK files or decompiled proprietary source;
- signing certificates or provisioning profiles;
- database, Redis, MongoDB, MQ, RTC, IM, payment, SMS, or cloud secrets;
- copied brand, gift, illustration, or animation assets.

Use interfaces, redacted schemas, and local fake implementations. Production values belong in the deployment secret store and must be injected at build or runtime.
