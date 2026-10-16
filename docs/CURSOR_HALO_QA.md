# Cursor halo and held mouse buttons

The left hand moves and presses the actual mouse. The right hand retains profile actions and the Deepwork red laser.

| State | Feedback |
| --- | --- |
| Initial closure, missing/incomplete hand, stopped controls | Hidden |
| Armed left mouse, including a forming button pose | Short entry, then static ring |
| Accepted button down or discrete shortcut | One 0.22 s pulse |
| Button held, including while the right laser is visible | Thicker static ring |
| Open palm, tracking loss/expiry, mode/permission change | Release owned button and fade |
| Halo disabled | No visual; button safety remains active |
| Right laser active without a held mouse button | Ready ring suppressed |

The mouse keeps its relative wrist/palm anchor across finger changes. Thumb + index retains Deepwork scroll priority and releases a held mouse button before scrolling. Thumb + ring holds left, thumb + middle holds middle, and curled fingers with the thumb extended hold right. A stable pose precedes button down; a direct switch releases before the next down. If event submission fails, cleanup is retried and new downs stay blocked until release succeeds.

## Automated checks

Run `swift test --jobs 1` for offline validation. The SwiftPM harness excludes UI and app entry points, injects camera-free trackers and an action recorder, and does not post real input events. Tests cover button poses, press/hold/up, switches, drag event types, wrist-anchor continuity, scroll arbitration, invalid observations, reentrant stop, permission changes, cleanup retry, the capture watchdog, diagnostic counts, laser coexistence, and visual state/persistence.

Synthetic tests and a successful build do not establish physical gesture accuracy, live event delivery, or visual usability. Camera and Accessibility permissions must be checked separately during a manual session.

## Manual checks

1. Confirm the Gestures switch remains visible while the guide or settings scroll. Confirm the left label follows the physical left hand. Close/relax to arm, then move the wrist and observe a quiet ring.
2. Test thumb + ring for left, thumb + middle for middle, and curled fingers + extended thumb for right. Holding must produce one down and a thicker static ring; moving must drag with that button. Changing fingers at a fixed wrist must not jump. Release or open the palm to let go.
3. Switch directly among all three buttons. The old button must release before the new press. Remove the hand, pause, switch mode, enter diagnostic mode, or stop: no button should remain held.
4. Turn Gestures off during each hold and during scroll/right commands. Verify release, stopped events, and hidden overlays. Turn it on while still holding a command: nothing may fire until that hand shows neutral. Check preference persistence.
5. Confirm thumb + index plus wrist displacement still scrolls in Deepwork and closed-hand movement remains available.
6. Disable the halo while dragging. The drag must continue; tracking loss must still release it. Relaunch to check the saved preference.
7. Try the right-hand shortcuts and Deepwork red laser. They must not move or press the actual mouse. A left-button hold remains visually distinct while the laser is visible.
8. Check bright/dark targets, Increase Contrast, Reduce Motion, full-screen apps, and mixed-scale/negative-coordinate displays. The hollow ring must pass clicks through and never take focus.
