import android.view.InputDevice;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;

/** Read-only Android hardware keyboard diagnosis; no app/account data is read. */
public final class KeyboardMapProbe {
  public static void main(String[] args) {
    for (java.lang.reflect.Method method : KeyCharacterMap.class.getDeclaredMethods()) {
      if (method.getName().toLowerCase().contains("load") || method.getName().toLowerCase().contains("read")) System.out.println(method.toString());
    }
    try {
      Class<?> manager = Class.forName("android.hardware.input.InputManagerGlobal");
      Object globalInputManager = manager.getMethod("getInstance").invoke(null);
      for (java.lang.reflect.Method method : manager.getDeclaredMethods()) {
        if (method.getName().contains("KeyboardLayout")) System.out.println(method.toString());
      }
      Class<?> publicManager = Class.forName("android.hardware.input.InputManager");
      if (android.os.Looper.myLooper() == null) android.os.Looper.prepareMainLooper();
      Class<?> activityThread = Class.forName("android.app.ActivityThread");
      Object thread = activityThread.getMethod("systemMain").invoke(null);
      android.content.Context context = (android.content.Context)activityThread.getMethod("getSystemContext").invoke(thread);
      Object inputManager = context.getSystemService(android.content.Context.INPUT_SERVICE);
      Object[] allLayouts = (Object[])publicManager.getMethod("getKeyboardLayouts").invoke(inputManager);
      for (Object layout : allLayouts) {
        String descriptor = (String)layout.getClass().getMethod("getDescriptor").invoke(layout);
        if (descriptor.matches("(?i).*(english_us|turkish).*")) System.out.println("AVAILABLE " + descriptor);
      }
      android.view.inputmethod.InputMethodManager ime = (android.view.inputmethod.InputMethodManager)context.getSystemService(android.content.Context.INPUT_METHOD_SERVICE);
      for (android.view.inputmethod.InputMethodInfo info : ime.getInputMethodList()) {
        if (!info.getId().contains("inputmethod.latin")) continue;
        for (int index=0; index<info.getSubtypeCount(); index++) {
          android.view.inputmethod.InputMethodSubtype subtype=info.getSubtypeAt(index);
          if (subtype.hashCode()!=-1966507396) continue;
          for (int id : InputDevice.getDeviceIds()) {
            InputDevice device=InputDevice.getDevice(id);
            if (id<0 || device.getKeyboardType()!=InputDevice.KEYBOARD_TYPE_ALPHABETIC) continue;
            Object deviceIdentifier=InputDevice.class.getMethod("getIdentifier").invoke(device);
            Object selection=publicManager.getMethod("getKeyboardLayoutForInputDevice", deviceIdentifier.getClass(), int.class, android.view.inputmethod.InputMethodInfo.class, android.view.inputmethod.InputMethodSubtype.class).invoke(inputManager, deviceIdentifier, 0, info, subtype);
            System.out.println("SELECTED " + id + " " + device.getName() + " " + selection);
            if (args.length > 0 && (args[0].equals("set-us") || args[0].equals("restore"))) {
              String override = args[0].equals("set-us")
                ? "com.android.inputdevices/com.android.inputdevices.InputDeviceReceiver/keyboard_layout_english_us"
                : "com.android.inputdevices/com.android.inputdevices.InputDeviceReceiver/keyboard_layout_turkish";
              manager.getMethod("setKeyboardLayoutOverrideForInputDevice", deviceIdentifier.getClass(), String.class)
                .invoke(globalInputManager, deviceIdentifier, override);
              System.out.println("OVERRIDE " + id + " " + override);
            }
          }
        }
      }
      Object instance = manager.getMethod("getInstance").invoke(null);
      Object identifier = InputDevice.class.getMethod("getIdentifier").invoke(InputDevice.getDevice(0));
      Object[] layouts = (Object[])manager.getMethod("getKeyboardLayoutsForInputDevice", identifier.getClass()).invoke(instance, identifier);
      for (Object layout : layouts) {
        String label = (String)layout.getClass().getMethod("getLabel").invoke(layout);
        if (label.matches("(?i).*(english|turkish|türkçe).*")) {
          System.out.println("LAYOUT " + label + " " + layout.getClass().getMethod("getDescriptor").invoke(layout));
        }
      }
    } catch (Exception error) { System.out.println(error.toString()); }
    for (int id : InputDevice.getDeviceIds()) {
      InputDevice device = InputDevice.getDevice(id);
      if (device == null || device.getKeyboardType() != InputDevice.KEYBOARD_TYPE_ALPHABETIC) continue;
      System.out.println("DEVICE " + id + " " + device.getName());
      KeyCharacterMap map = device.getKeyCharacterMap();
      for (int key : new int[]{KeyEvent.KEYCODE_I, KeyEvent.KEYCODE_APOSTROPHE, KeyEvent.KEYCODE_SEMICOLON}) {
        System.out.printf("%s normal=U+%04X shift=U+%04X%n",
          KeyEvent.keyCodeToString(key), map.get(key, 0), map.get(key, KeyEvent.META_SHIFT_ON));
      }
    }
  }
}
