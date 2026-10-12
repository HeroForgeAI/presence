# Security

## Reporting a problem

Please report security problems privately, not in a public issue.

Use GitHub's private reporting: open the repository's **Security** tab and choose **Report a vulnerability**, or go straight to <https://github.com/HeroForgeAI/presence/security/advisories/new>.

Include your Mac model, macOS version, and the steps that show the problem. **Do not include a recording, a screenshot of a real meeting, or someone else's face.**

You can expect a first reply within a week.

## Supported versions

| Version | Supported |
| --- | --- |
| `main` | yes |

There is no numbered release yet. The source on `main` is what this covers.

## What the app does, in security terms

- **The take stays in memory.** Frames of the take are not written to disk. Quit the app and the take is gone.
- **The webcam is the real one.** Presence does not offer its own output, or another virtual camera, as the camera it records from.
- **Zoom backgrounds are read, not uploaded.** The app lists image and video files Zoom already stored on that Mac. It does not send them anywhere.
- **The build is unsigned unless you sign it.** An ad-hoc build can run on your Mac. macOS will not install its camera extension, and each rebuild can ask for Camera permission again. Turning off SIP or Gatekeeper is not a workaround this project will suggest or accept.
- **No account, no telemetry.** The app does not phone home.

## In scope

- A way to make the app write a take to disk when the person did not ask it to.
- A way to capture a virtual camera and feed it back out, so the picture loops on itself.
- A leaked secret in the repository.

## Out of scope

- Zoom, OBS, or Elgato being closed or misconfigured.
- A person choosing to send the loop while they are still visibly doing something else.
- Gatekeeper refusing an app that a browser downloaded. The README says how to allow that one app.
