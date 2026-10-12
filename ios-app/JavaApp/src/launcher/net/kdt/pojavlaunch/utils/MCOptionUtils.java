package net.kdt.pojavlaunch.utils;

import java.util.*;
import java.io.*;

import net.kdt.pojavlaunch.*;

public class MCOptionUtils
{
    private static List<String> mLineList;
    
    public static void load() {
        if (mLineList == null) {
            mLineList = new ArrayList<String>();
        } else {
            mLineList.clear();
        }
        
        try {
            BufferedReader reader = new BufferedReader(new FileReader(Tools.DIR_GAME_PROFILE + "/options.txt"));
            String line;
            while ((line = reader.readLine()) != null) {
                mLineList.add(line);
            }
            reader.close();
        } catch (IOException e) {
            System.err.println("Could not load options.txt");
            e.printStackTrace();
        }
    }
    
    public static void set(String key, String value) {
        // Task 104: Deduplicate writes. MC's Options.load calls putString for each line;
        // when a key appears multiple times, the last line overrides earlier ones.
        // The old implementation changed only the first duplicate, so later stale
        // values overrode ours (for example, a leftover inactivityFpsLimit:afk
        // made the minimized setting ineffective and triggered MC 26.3's
        // SHORT_AFK 30 FPS limit). Now the first occurrence is replaced and all
        // subsequent duplicates are removed.
        String prefix = key + ":";
        boolean replaced = false;
        ListIterator<String> it = mLineList.listIterator();
        while (it.hasNext()) {
            String line = it.next();
            if (line.startsWith(prefix)) {
                if (!replaced) {
                    it.set(key + ":" + value);
                    replaced = true;
                } else {
                    it.remove(); // Remove duplicates because MC uses the last matching line.
                }
            }
        }
        if (!replaced) {
            mLineList.add(key + ":" + value);
        }
    }

    public static void setDefault(String key, String value) {
        if (get(key) == null) {
            mLineList.add(key + ":" + value);
        }
    }

    /**
     * Remove the line for the specified key from options.txt, if present.
     * Used when the user selects "Default" to clear a previously written value
     * and let MC use its internal default behavior.
     * Call load() first.
     */
    public static void remove(String key) {
        if (mLineList == null) return;
        String prefix = key + ":";
        for (int i = 0; i < mLineList.size(); i++) {
            if (mLineList.get(i).startsWith(prefix)) {
                mLineList.remove(i);
                return;
            }
        }
    }

    public static String get(String key){
        if (mLineList == null){
            load();
        }
        for (int i = 0; i < mLineList.size(); i++) {
            String line = mLineList.get(i);
            if (line.startsWith(key + ":")) {
                String value = mLineList.get(i);
                return value.substring(value.indexOf(":")+1);
            }
        }
        return null;
    }

    public static void save() {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < mLineList.size(); i++) {
            result.append(mLineList.get(i));
            if (i + 1 < mLineList.size()) {
                result.append("\n");
            }
        }
        
        try {
            Tools.write(Tools.DIR_GAME_PROFILE + "/options.txt", result.toString());
        } catch (IOException e) {
            System.err.println("Could not save options.txt");
            e.printStackTrace();
        }
        mLineList = null;
    }

    /**
     * Task 104: Read the specified key's value back from disk (bypassing the in-memory list).
     * Used to verify the file after save(): an in-memory get() confirms only the
     * in-memory state, not what MC will read. A wrong path, failed write, or
     * leftover duplicate can make memory and disk diverge; MC 26.3's 30 FPS
     * throttling was a confirmed example.
     */
    public static String getFromFile(String key) {
        try {
            BufferedReader reader = new BufferedReader(new FileReader(Tools.DIR_GAME_PROFILE + "/options.txt"));
            String line;
            String last = null;
            int occurrences = 0;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith(key + ":")) {
                    last = line.substring(line.indexOf(":") + 1);
                    occurrences++;
                }
            }
            reader.close();
            if (occurrences > 1) {
                System.out.println("[MCOptionUtils] Task104 WARNING: '" + key + "' appears " + occurrences
                    + " times in options.txt (last-wins at MC side): " + last);
            }
            return last;
        } catch (IOException e) {
            return "<read-failed: " + e.getClass().getSimpleName() + ">";
        }
    }
}
