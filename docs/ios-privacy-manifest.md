# Apple privacy manifest

This file documents the engineering evidence behind the app-level
`ios/Runner/PrivacyInfo.xcprivacy` for the current iOS host. It is not legal approval,
an App Store privacy nutrition-label submission, or a substitute for the final
product owner's privacy review.

## Current first-party data evidence

The current Flutter client sends the following account and product data to its
first-party backend for app functionality:

- `NSPrivacyCollectedDataTypeName`: the registration nickname and displayed
  profile name.
- `NSPrivacyCollectedDataTypePhoneNumber`: SMS login and registration.
- `NSPrivacyCollectedDataTypeUserID`: authenticated user and relationship
  identifiers used by the product flows.
- `NSPrivacyCollectedDataTypeDeviceID`: the locally generated installation
  identifier sent as the device/session identity.
- `NSPrivacyCollectedDataTypeOtherUserContent`: first-party messages,
  comments, and dynamic content submitted through the product flows.
- `NSPrivacyCollectedDataTypePurchaseHistory`: recharge orders, wallet purchase
  records, and the related first-party order history.
- `NSPrivacyCollectedDataTypeSearchHistory`: user-entered room and user search
  terms sent to the first-party search routes.
- `NSPrivacyCollectedDataTypeProductInteraction`: first-party room, gift, and
  social relationship interactions such as follow actions.
- `NSPrivacyCollectedDataTypeCustomerSupport`: report, appeal, and support
  ticket text submitted to first-party review/support routes.

These entries are marked linked to the user's account, used for app
functionality, and not used for tracking. The app manifest deliberately has no
tracking domains and no app-owned Required Reason API declarations: the source
review found no app-owned use of the covered File Timestamp, System Boot Time,
Disk Space, User Defaults, or Active Keyboards APIs.

## Permission and SDK boundary

The iOS host declares microphone, camera, photo-library, and notification
permission purpose strings in `Info.plist`. A permission prompt alone is not a
declaration that the app collected a data type. The current dynamic image
publisher still fails closed with “image upload not configured”, so
Photos/Videos are not claimed as currently collected by the first-party upload
path in this manifest. Product/legal owners must revisit this before enabling
image upload or changing the profile media flow.

Agora RTC, Tencent IM, Flutter Secure Storage, and other third-party SDKs must
be audited against the exact locked versions and their vendor-supplied privacy
manifests. Their SDK manifests remain the authoritative source for data and
Required Reason API declarations owned by those SDKs; this app-level manifest
does not invent vendor collection claims. In particular, audio/RTC, IM
transport, keychain storage, and notification delivery require external owner
input for the final App Store privacy disclosures.

The following items remain external owner input rather than facts asserted by
this file:

- the final legal classification of linked account data and user-generated
  content;
- the vendor privacy manifests and current data-use terms for Agora and
  Tencent IM;
- whether any future analytics, advertising, attribution, or tracking SDK is
  added;
- the final declaration if photo/video upload, push provider, or other vendor
  capability is enabled.

## Validation boundary

The contract test checks that the manifest is valid app-owned source, is
referenced by the Runner Xcode target's Resources phase, and is copied to the
root of the built `.app` bundle. The manifest is an engineering baseline, not
legal approval.
