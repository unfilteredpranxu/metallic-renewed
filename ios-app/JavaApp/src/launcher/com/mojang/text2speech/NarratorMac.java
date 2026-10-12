package com.mojang.text2speech;

/**
 * Task 73: The macOS narrator class in the real text2speech 1.19.12 library
 * is named NarratorMac (an older stub incorrectly called it NarratorOSX).
 *
 * None of the 51 mods in the current client 26.2/26.3 and FO v14.1.0
 * directly reference this class. This defensive addition aligns the API:
 * if a future mod (or a newer ModernFix) constructs NarratorMac through the
 * OperatingSystem.get()==MAC_OS branch, the symbol will be available.
 * Like NarratorDummy, it is always empty because iOS has no AppKit speech synthesis.
 */
public class NarratorMac extends NarratorDummy {
}
