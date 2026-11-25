import android.view.InputDevice;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;

/** Read-only check of the emulator's live physical keyboard maps. */
public final class VerifyTurkishPhysicalMap {
  public static void main(String[] args) throws Exception {
    int[] scans = {40, 23, 39, 51, 53, 26, 27, 16};
    String[] names = {"APOSTROPHE", "I", "SEMICOLON", "COMMA", "SLASH",
      "LEFT_BRACKET", "RIGHT_BRACKET", "Q"};
    int[][] expected = {{0x69,0x130},{0x131,0x49},{0x15f,0x15e},
      {0xf6,0xd6},{0x2e,0x3a},{0x11f,0x11e},{0xfc,0xdc},{0x71,0x51}};
    int checked = 0;
    for (int id : InputDevice.getDeviceIds()) {
      InputDevice device = InputDevice.getDevice(id);
      if (id < 0 || device.getKeyboardType() != InputDevice.KEYBOARD_TYPE_ALPHABETIC) continue;
      KeyCharacterMap map = device.getKeyCharacterMap();
      java.lang.reflect.Method remap = KeyCharacterMap.class.getMethod(
        "getMappedKeyOrDefault", int.class, int.class);
      for (int index=0; index<scans.length; index++) {
        int key=(Integer)remap.invoke(map,scans[index],KeyEvent.keyCodeFromString("KEYCODE_"+names[index]));
        int normal=map.get(key,0);
        int shift=map.get(key,KeyEvent.META_SHIFT_ON|KeyEvent.META_SHIFT_LEFT_ON);
        if(normal!=expected[index][0] || shift!=expected[index][1]) {
          throw new AssertionError(device.getName()+" scan="+scans[index]+
            " normal=U+"+Integer.toHexString(normal)+" shift=U+"+Integer.toHexString(shift));
        }
      }
      int at=map.get(KeyEvent.KEYCODE_Q,KeyEvent.META_ALT_ON|KeyEvent.META_ALT_RIGHT_ON);
      if(at!=0x40) throw new AssertionError("AltGr+Q did not map to @ on "+device.getName());
      int cedilla=(Integer)remap.invoke(map,52,KeyEvent.KEYCODE_PERIOD);
      if(map.get(cedilla,0)!=0xe7 || map.get(cedilla,KeyEvent.META_SHIFT_ON)!=0xc7) {
        throw new AssertionError("Cedilla mapping failed on "+device.getName());
      }
      System.out.println("PASS "+device.getName()+" Turkish Q letters, Shift and AltGr+Q");
      checked++;
    }
    if(checked==0) throw new AssertionError("No physical keyboard found");
    System.out.println("PASS physical keyboards checked="+checked);
  }
}
