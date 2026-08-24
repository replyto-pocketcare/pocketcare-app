package com.sanvya.app.ui.shell

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The window-class mapping, at the breakpoints and on real devices.
 *
 * These read as obvious, which is the point: the failure mode they guard is a
 * flipped comparison or a dropped height check, and both look obvious too right
 * up until someone opens the app on a foldable.
 */
class WindowClassTest {

    @Test
    fun `material breakpoints decide the class`() {
        // 600dp: labels appear on the bottom bar.
        assertEquals(SanvyaWindowClass.COMPACT, windowClassOf(599, 900))
        assertEquals(SanvyaWindowClass.MEDIUM, windowClassOf(600, 900))

        // 840dp: the sidebar takes over from the bottom bar.
        assertEquals(SanvyaWindowClass.MEDIUM, windowClassOf(839, 900))
        assertEquals(SanvyaWindowClass.EXPANDED, windowClassOf(840, 900))
    }

    @Test
    fun `a wide but short window does not get the sidebar`() {
        // The sidebar is a full-height column. Give it a 400dp-tall window and
        // the content is left in a letterbox -- so height gates it too.
        assertEquals(SanvyaWindowClass.MEDIUM, windowClassOf(1000, 400))
        assertEquals(SanvyaWindowClass.EXPANDED, windowClassOf(1000, 480))
    }

    @Test
    fun `real devices land where the platform would put them`() {
        // Phone, portrait -- the only orientation a phone is allowed.
        assertEquals(SanvyaWindowClass.COMPACT, windowClassOf(412, 892))

        // Pixel Fold on its cover display, both ways up.
        assertEquals(SanvyaWindowClass.COMPACT, windowClassOf(415, 800))
        assertEquals(SanvyaWindowClass.MEDIUM, windowClassOf(800, 415))

        // Pixel Fold open: big enough for the sidebar either way up.
        assertEquals(SanvyaWindowClass.EXPANDED, windowClassOf(849, 707))

        // A 10" tablet, portrait then landscape.
        assertEquals(SanvyaWindowClass.MEDIUM, windowClassOf(800, 1280))
        assertEquals(SanvyaWindowClass.EXPANDED, windowClassOf(1280, 800))

        // The same tablet with the app in a narrow split-screen pane: the app
        // gets the phone layout, because the app is phone-sized. Window, not
        // display -- this is the whole reason we ask the window.
        assertEquals(SanvyaWindowClass.COMPACT, windowClassOf(480, 800))
    }

    @Test
    fun `capability flags follow from the class`() {
        assertFalse(SanvyaWindowClass.COMPACT.showsNavLabels)
        assertTrue(SanvyaWindowClass.MEDIUM.showsNavLabels)

        assertTrue(SanvyaWindowClass.COMPACT.usesBottomBar)
        assertTrue(SanvyaWindowClass.MEDIUM.usesBottomBar)
        assertFalse(SanvyaWindowClass.EXPANDED.usesBottomBar)

        assertFalse(SanvyaWindowClass.COMPACT.capsContentWidth)
        assertTrue(SanvyaWindowClass.MEDIUM.capsContentWidth)
    }

    @Test
    fun `only phones are locked to portrait`() {
        assertTrue(SanvyaDeviceType.PHONE.lockedToPortrait)
        assertFalse(SanvyaDeviceType.TABLET.lockedToPortrait)
        assertFalse(SanvyaDeviceType.FOLDABLE.lockedToPortrait)
    }
}
