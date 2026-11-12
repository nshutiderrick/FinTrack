// Non-secret service configuration. Nothing here grants access on its own:
// Firestore is protected by firestore.rules, and Cloudinary uploads only go
// through the unsigned preset's restrictions.

/// Firebase project "finance tracker".
const firebaseProjectId = 'finance-tracker-c9664';

/// OAuth "Web client" ID that Google sign-in needs on Android. Firebase creates
/// it when the Google provider is enabled under Authentication > Sign-in method.
const googleWebClientId = '399136486751-5hmmiq2l2c9eqjcnhaimp48h6os5dq7g.apps.googleusercontent.com';

const cloudinaryCloudName = 'i22njbjq';
const cloudinaryUploadPreset = 'finance_tracker_unassigned';

/// EmailJS sends the "Forgot passcode" code. The public key is meant to be in
/// apps; the template sends to {{to_email}} with {{code}} in the message.
const emailJsServiceId = 'service_z32ss3p';
const emailJsTemplateId = 'template_8ahqete';
const emailJsPublicKey = '0manh4RGycYOl4_t7';
