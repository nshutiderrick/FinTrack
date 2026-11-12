/// Set right before the app itself opens something outside it (camera, file
/// picker, Android settings, Google sign-in), so the passcode lock does not ask
/// again when I come back. Cleared when the app is back in front.
bool expectingExternal = false;

void expectExternal() => expectingExternal = true;
