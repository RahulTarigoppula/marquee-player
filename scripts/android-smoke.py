#!/usr/bin/env python3
"""Marquee on a running Android: the lock-screen controls and background sound, for real.

    python3 scripts/android-smoke.py <marquee.apk> <film.mp4> [evidence-dir]

Needs one device or emulator on adb (Android 13+). It installs the APK, opens the film through
"Open with" and then only does what a person could do from outside the app: media keys, the
power button, a headset button, Back. What it reads back is what Android itself reports (`dumpsys`), never the
app's own word:

  1. the film reaches the system's media controls, playing, with a foreground service
  2. pause and play from a media key
  3. the screen goes off -> the film pauses (background play is off by default)
  4. play from the dark screen -> the sound really runs: the position moves on
  5. back in the app nothing has crashed, and closing the film removes the controls

Exit 0 when every step held; 1 with the step that did not. Evidence (logcat, dumps, a
screenshot) is written either way.
"""
import os
import re
import subprocess
import sys
import time

PKG = "com.rahul.marquee"
ACTIVITY = f"{PKG}/.MainActivity"
FILM_ON_DEVICE = "/sdcard/Movies/marquee-smoke.mp4"

PAUSED, PLAYING, BUFFERING = 2, 3, 6
KEY_BACK, KEY_MEDIA_PLAY, KEY_MEDIA_PAUSE, KEY_SLEEP, KEY_WAKEUP = 4, 126, 127, 223, 224


def adb(*args, check=True, timeout=120):
    done = subprocess.run(
        ["adb", *args], capture_output=True, text=True, errors="replace", timeout=timeout
    )
    if check and done.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {done.stdout}{done.stderr}")
    return done.stdout


def shell(command, check=True):
    return adb("shell", command, check=check)


def key(code):
    shell(f"input keyevent {code}")


def media_button(name):
    """A headset's button. `input keyevent` cannot stand in for one while the screen is off:
    Android hands an injected key to the focused window, and a dark screen has none, so the
    key is dropped before any app sees it. This goes where a real button goes."""
    shell(f"cmd media_session dispatch {name}")


class Failed(Exception):
    pass


def step(text):
    print(f"\n== {text}", flush=True)


def session():
    """Marquee's media session as Android reports it: (state, position ms), or None."""
    dump = shell("dumpsys media_session", check=False)
    at = dump.find(f"package={PKG}")
    if at < 0:
        return None
    # API 33 prints `state=3`, API 34+ `state=PLAYING(3)`.
    found = re.search(
        r"state=PlaybackState \{state=(?:[A-Z_]+\()?(\d+)\)?, position=(-?\d+)",
        dump[at : at + 1500],
    )
    return (int(found.group(1)), int(found.group(2))) if found else None


def service_is_foreground():
    dump = shell(f"dumpsys activity services {PKG}", check=False)
    at = dump.find("PlaybackService")
    return at >= 0 and "isForeground=true" in dump[at : at + 3000]


def wait_for(what, check, seconds):
    """Polls until check() is truthy and returns that value."""
    deadline = time.time() + seconds
    last = None
    while time.time() < deadline:
        last = check()
        if last:
            print(f"   ok: {what}", flush=True)
            return last
        time.sleep(1)
    raise Failed(f"{what} (waited {seconds} s; media session: {session()})")


def in_state(*states):
    def check():
        now = session()
        return now if now is not None and now[0] in states else None

    return check


def film_id():
    rows = shell(
        "content query --uri content://media/external/video/media "
        "--projection _id:_display_name",
        check=False,
    )
    found = re.search(r"_id=(\d+), _display_name=marquee-smoke\.mp4", rows)
    return found.group(1) if found else None


def collect(out):
    def save(name, text):
        with open(os.path.join(out, name), "w", encoding="utf-8", errors="replace") as f:
            f.write(text)

    try:
        save("logcat.txt", adb("logcat", "-d", check=False))
        save("crash.txt", adb("logcat", "-d", "-b", "crash", check=False))
        save("media_session.txt", shell("dumpsys media_session", check=False))
        save("services.txt", shell(f"dumpsys activity services {PKG}", check=False))
        save("notifications.txt", shell("dumpsys notification --noredact", check=False))
    except Exception as e:  # evidence must never hide the real result
        print(f"   (evidence incomplete: {e})")


def screenshot(out, name):
    try:
        png = subprocess.run(
            ["adb", "exec-out", "screencap", "-p"], capture_output=True, timeout=60
        ).stdout
        with open(os.path.join(out, name), "wb") as f:
            f.write(png)
    except Exception as e:
        print(f"   (no screenshot: {e})")


def run(apk, film, out):
    step("install, and put a film on the device")
    adb("install", "-r", apk, timeout=300)
    shell(f"pm grant {PKG} android.permission.READ_MEDIA_VIDEO", check=False)
    shell("mkdir -p /sdcard/Movies", check=False)
    adb("push", film, FILM_ON_DEVICE, timeout=300)
    shell(
        "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE "
        f"-d file://{FILM_ON_DEVICE}",
        check=False,
    )
    media = wait_for("the film is in the device's video library", film_id, 60)

    step("open it the way a file manager would")
    key(KEY_WAKEUP)
    shell("wm dismiss-keyguard", check=False)
    adb("logcat", "-c", check=False)
    shell(
        f"am start -W -n {ACTIVITY} -a android.intent.action.VIEW "
        f"-d content://media/external/video/media/{media} -t video/mp4 "
        "--grant-read-uri-permission"
    )
    started = wait_for(
        "the film is on the system's media controls, playing", in_state(PLAYING), 180
    )
    wait_for("the playback service is in the foreground", service_is_foreground, 20)
    time.sleep(5)
    screenshot(out, "playing.png")

    step("pause and play from a media key")
    key(KEY_MEDIA_PAUSE)
    paused = wait_for("paused", in_state(PAUSED), 20)
    if paused[1] - started[1] < 1500:
        raise Failed(
            f"the film did not move while it played: {started[1]} ms -> {paused[1]} ms"
        )
    print(f"   ok: it played from {started[1]} ms to {paused[1]} ms")
    wait_for(
        "paused: the service has left the foreground",
        lambda: not service_is_foreground(),
        20,
    )
    key(KEY_MEDIA_PLAY)
    wait_for("playing again", in_state(PLAYING), 20)

    step("screen off: the film pauses (background play is off by default)")
    key(KEY_SLEEP)
    wait_for("paused by the screen going off", in_state(PAUSED), 30)

    step("play from the dark screen: the sound carries on")
    media_button("play")
    dark = wait_for("playing with the screen off", in_state(PLAYING), 30)
    wait_for("the playback service is in the foreground again", service_is_foreground, 20)
    time.sleep(8)
    media_button("pause")
    after = wait_for("paused from the dark screen", in_state(PAUSED), 20)
    if after[1] - dark[1] < 4000:
        raise Failed(
            f"the film did not move with the screen off: {dark[1]} ms -> {after[1]} ms"
        )
    print(f"   ok: it played unseen from {dark[1]} ms to {after[1]} ms")

    step("back in the app: nothing crashed, and closing the film removes the controls")
    key(KEY_WAKEUP)
    shell("wm dismiss-keyguard", check=False)
    shell(f"am start -W -n {ACTIVITY}")
    time.sleep(3)
    if not shell(f"pidof {PKG}", check=False).strip():
        raise Failed("the app is no longer running")
    crashes = adb("logcat", "-d", "-b", "crash", check=False)
    if PKG in crashes:
        raise Failed("the app crashed (see crash.txt)")
    screenshot(out, "returned.png")
    for _ in range(3):
        key(KEY_BACK)
        time.sleep(4)
        if session() is None:
            break
    wait_for("the media controls are gone", lambda: session() is None, 20)
    wait_for(
        "the playback service has stopped",
        lambda: "PlaybackService" not in shell(f"dumpsys activity services {PKG}", check=False),
        20,
    )


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    apk, film = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else "build/android-smoke"
    os.makedirs(out, exist_ok=True)
    try:
        run(apk, film, out)
    except (Failed, RuntimeError, subprocess.TimeoutExpired) as e:
        screenshot(out, "failed.png")
        collect(out)
        print(f"\n::error title=Android smoke test::{e}")
        return 1
    collect(out)
    print("\nAndroid smoke test passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
