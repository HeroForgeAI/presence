# Contributing to Presence

**The short version.** Ideas and fixes are welcome. Everything comes in as a pull request from your own fork. Mak Allen approves it before it merges. You do not get write access by opening an issue, and a pull request is not a promise that it will merge.

You do not need to be a programmer to help. A clear bug report, a confusing sentence, or a note that it worked or did not work on your Mac are real contributions.

This is a small Mac app with a narrow promise: you step away, and the meeting still sees the take you just recorded. The most useful contributions keep that promise.

## Before anything else: never share a real take

A take is a picture of a person on a call. **Never attach a recording, a screenshot of a real meeting, or someone else’s face to an issue or a pull request.** Describe the bug in words. If a picture is required, use a stand-in, not a person from a call.

## Where to ask a question

Open an issue and pick **A question, or help getting set up**. No question is too basic.

## Requesting a feature

Open an issue and pick **[A feature](https://github.com/HeroForgeAI/presence/issues/new?template=feature.md)**. One request per issue. Say the moment you would use it, and what the other person on the call should see. You do not have to be a programmer, and you do not have to build it.

Mak Allen reads these. He says yes, not like that, or no. A no comes with a reason. A yes means a pull request from your fork is welcome. It does not promise a date, and it does not put the change on `main` by itself. Opening the issue does not grant write access.

If you want to build it, wait for the yes, then follow the steps below. A pull request for a feature nobody has said yes to, when it is bigger than a small fix, is how an evening gets thrown away.

A request that crosses a [hard line](#the-hard-lines) needs an explicit yes before any code. If you are not sure, say so in the issue.

The same rule as everything else: no recording, no screenshot of a real meeting, and no one else's face.

## Reporting a bug

Open an issue with the bug form. Say which Mac, which macOS, which webcam, and which camera Zoom is set to. Say what you expected the other person to see.

Security problems go through [SECURITY.md](SECURITY.md), in private, and never into a public issue.

## Proposing a change

For a typo or a small fix, go straight to a pull request.

For anything bigger, **open a feature issue first**. That way you hear yes, not like that, or no before you have spent an evening on it.

## Making the change

1. **Fork** the repo on GitHub. Nobody can push straight to `main`.
2. **Branch** from `main` in your fork.
3. **Set up** with Xcode 26 or later, on macOS 26 or later:

   ```bash
   git clone https://github.com/<your-name>/presence.git
   cd presence
   xcodegen generate
   ```

4. **Change** one thing.
5. **Run the tests:**

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -scheme Presence -destination 'platform=macOS' test
   ```

   There is no GitHub Actions run yet. Say which Mac you ran this on. If you could not run it, say that in the pull request.
6. **Open a pull request** against `main`. Fill in the template.

## What a good pull request looks like

- **One change.** Two fixes are two pull requests.
- **A test** that fails without your change, when the change is logic that can be tested without a camera.
- **A plain commit message** that says what changed.
- **One line in `CHANGELOG.md`** under **Unreleased**.
- **No real take** anywhere: not in the diff, and not in the description.
- **No secrets.** Keys, tokens, and passwords stay out of the repo.

## What happens next

1. A maintainer reads it, usually within a few days. Expect questions. That is normal.
2. Mak Allen approves and merges it as one squashed commit. Every merge needs his approval. If you push again after he has said yes, the new version is looked at again.

A pull request that goes quiet gets a polite nudge after two weeks and is closed after four, with an invitation to reopen it. See [GOVERNANCE.md](GOVERNANCE.md).

## Who decides

Mak Allen ([@HF-teamdev](https://github.com/HF-teamdev)) merges. He may say no. When he does, it will be kind and it will come with a reason.

Write access is by invitation, after sustained good contributions. There is no application, and opening a pull request does not grant it.

## The hard lines

These are the edges of the project. A change that crosses one needs an issue and an explicit yes first.

- **Mac only.** Meet and Teams are in scope when they can select the same virtual camera. Windows and Linux are not.
- **Swift stays.** The camera extension and the interface are Apple frameworks. A Rust port is out.
- **The take stays in memory** for the session. It is not a ring buffer, and it is not a clip saved to disk.
- **No one’s background is hardcoded.** Each person picks from the backgrounds on their own Mac.
- **No DAL plugin,** and no instructions to turn off SIP or Gatekeeper. Those are not fixes.
- **Do not claim Zoom lists a camera named Presence** until a build signed with a paid Apple Developer certificate actually does. Until then the picture goes out through OBS Virtual Camera or Elgato Virtual Camera.
- **Do not vendor OBS,** and do not copy another project’s camera extension into this tree.

The useful work is the picture the other person sees: a join that does not hitch, a crop that does not jump, a background that matches the meeting, and a long call that does not spin the fan the whole time.
