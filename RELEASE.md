# Publishing stacker_inspector — a step-by-step guide

This guide assumes you have **never published a library before**. Every command
is shown in full, and every step says what "success" looks like so you can tell
whether it worked.

This library ships from **one repository** to **three channels**:

| Channel | Who uses it | What they get |
|---|---|---|
| **pub.dev** | Flutter & hybrid apps | The Dart package (`flutter pub add stacker_inspector`) |
| **JitPack** | Native Android apps | Prebuilt `.aar` files, one Gradle line |
| **CocoaPods** | Native iOS apps | Prebuilt `.xcframework` files, one Podfile line |

You can do them in any order, but the order below is easiest because each step
builds on the previous one.

---

## Table of contents

- [Before you start](#before-you-start)
- [Step 0 — Replace the placeholders](#step-0--replace-the-placeholders)
- [Step 1 — Push to GitHub](#step-1--push-to-github)
- [Step 2 — Publish to pub.dev (Flutter)](#step-2--publish-to-pubdev-flutter)
- [Step 3 — Publish to JitPack (native Android)](#step-3--publish-to-jitpack-native-android)
- [Step 4 — Publish to CocoaPods (native iOS)](#step-4--publish-to-cocoapods-native-ios)
- [Step 5 — Verify all three](#step-5--verify-all-three)
- [Releasing a new version later](#releasing-a-new-version-later)
- [Troubleshooting](#troubleshooting)

---

## Before you start

### What you need

| | Needed for | How to check |
|---|---|---|
| A GitHub account | all three | `git --version` works and you can sign in to github.com |
| A Google account | pub.dev | any Gmail/Google Workspace account |
| Flutter SDK | all three | `flutter --version` prints 3.27 or newer |
| A Mac with Xcode | iOS only | `xcodebuild -version` prints something |
| CocoaPods | iOS only | `pod --version` prints 1.12+; install with `sudo gem install cocoapods` |

### One decision to make first

> ⚠️ **Which identity do you want in public git history?**
>
> Check your current one:
>
> ```bash
> git config user.email
> ```
>
> Commits are **permanent and public** once pushed. If that prints a work
> address and this is a personal project — or if your employer requires
> open-source review before you publish company-affiliated code — settle that
> now. Changing it later does not rewrite history that others have already
> cloned.
>
> To use a personal identity for this repository only:
>
> ```bash
> git config user.name  "Your Name"
> git config user.email "you@personal.example"
> ```
>
> If commits already exist and no one has cloned them yet, you can rewrite
> them:
>
> ```bash
> git rebase -r --root --exec \
>   'git commit --amend --no-edit --reset-author'
> ```

### A word about permanence

| Channel | Can you undo a release? |
|---|---|
| pub.dev | **No.** A version can be *retracted* (hidden from new installs) but never deleted or replaced. The version number is spent forever. |
| JitPack | Yes — delete the git tag and the build disappears. |
| CocoaPods | Trunk pushes are permanent; a GitHub-Release-based podspec can be re-uploaded. |

Because pub.dev is the unforgiving one, [Step 2](#step-2--publish-to-pubdev-flutter)
shows you how to publish a **prerelease** first.

---

## Step 0 — Replace the placeholders

The repository ships with `YOUR_USERNAME` and `YOUR_EMAIL` written into several
files. Replace them **before** publishing anything, or the links on pub.dev
and CocoaPods will be broken.

```bash
cd /path/to/stacker

# Replace both placeholders everywhere at once.
# On macOS, `sed -i ''` needs that empty argument — do not remove it.
grep -rl 'YOUR_USERNAME' \
  pubspec.yaml ios/stacker_inspector.podspec StackerInspector.podspec README.md RELEASE.md \
  | xargs sed -i '' 's/YOUR_USERNAME/your-github-username/g'

grep -rl 'YOUR_EMAIL' ios/stacker_inspector.podspec StackerInspector.podspec \
  | xargs sed -i '' 's/YOUR_EMAIL/you@example.com/g'
```

Also open `LICENSE` and put your name and the year in the copyright line.

**Check it worked** — this must print nothing:

```bash
grep -rn 'YOUR_USERNAME\|YOUR_EMAIL' \
  pubspec.yaml ios/stacker_inspector.podspec StackerInspector.podspec README.md
```

Then commit:

```bash
git add -A
git commit -m "Set repository URLs and author"
```

---

## Step 1 — Push to GitHub

All three channels read from a GitHub repository, so this comes first.

### 1.1 Create an empty repository

Go to **[github.com/new](https://github.com/new)** and set:

- **Repository name:** `stacker`
- **Visibility:** Public *(JitPack can do private repos, but that needs an auth
  token — start public unless you have a reason not to)*
- **Do NOT** tick "Add a README", ".gitignore", or "Choose a license" — the
  repository already has all three, and adding them creates a conflict.

Press **Create repository**.

### 1.2 Push

```bash
cd /path/to/stacker

# Skip this if `git log` already shows commits.
git init
git branch -M main
git add .
git commit -m "Initial release"

git remote add origin https://github.com/YOUR_USERNAME/stacker.git
git push -u origin main
```

**Check it worked:** reload the GitHub page — you should see your files and the
README rendered. `git status -sb` should print `## main...origin/main`.

### 1.3 Create the first tag

A tag marks the exact commit a release was built from. JitPack and CocoaPods
both need one.

```bash
git tag v0.1.0
git push origin v0.1.0
```

**Check it worked:** the repository's **Tags** page lists `v0.1.0`.

> **Naming:** tags use `v0.1.0` (with the `v`); the version inside
> `pubspec.yaml` and the podspecs is `0.1.0` (without). Keep them in step.

---

## Step 2 — Publish to pub.dev (Flutter)

This is what makes `flutter pub add stacker_inspector` work.

### 2.1 Check the package locally

```bash
cd /path/to/stacker
flutter pub get
cd stacker_host && flutter pub get && cd ..

flutter analyze
flutter test
flutter pub publish --dry-run
```

**What success looks like:**

```
No issues found!
All tests passed!
Total compressed archive size: 139 KB.
Package has 0 warnings.
```

> If the archive is **megabytes** instead of kilobytes, `.pubignore` is missing
> or broken. It exists to keep `stacker_host/` (the Flutter module, ~380 MB) out
> of the published package. Do not delete that file.

### 2.2 Publish a prerelease first (strongly recommended)

Because a pub.dev version can never be reused, publish a throwaway version
first and confirm it looks right.

Edit `pubspec.yaml`:

```yaml
version: 0.1.0-dev.1
```

Then:

```bash
flutter pub publish
```

You will be asked to confirm, then a browser opens for Google sign-in. Approve
it and return to the terminal.

**Check it worked:** open `https://pub.dev/packages/stacker_inspector` after a couple of
minutes. Confirm:

- the README renders and its links work (this is why Step 0 mattered);
- **Readme / Changelog / Example / Installing** tabs are all present;
- the score panel appears — 130/160 is a normal starting point.

A prerelease is **not** installed by `^` version constraints, so nobody picks it
up by accident.

### 2.3 Publish the real version

Set the version back:

```yaml
version: 0.1.0
```

```bash
git add pubspec.yaml
git commit -m "Release 0.1.0"
git push
flutter pub publish
```

**Check it worked:** `pub.dev/packages/stacker_inspector` shows `0.1.0`, and in a
throwaway project `flutter pub add stacker_inspector` resolves it.

---

## Step 3 — Publish to JitPack (native Android)

JitPack turns a git tag into Maven artifacts. There is no account setup and
nothing to upload — it builds from your repository on demand.

### 3.1 Register the repository

1. Go to **[jitpack.io](https://jitpack.io)** and **Sign in with GitHub**.
2. Paste `https://github.com/YOUR_USERNAME/stacker` into the search box.
3. Press **Look up**.

Your tag `v0.1.0` appears with a **Get it** button.

### 3.2 Trigger the build

Press **Get it**.

> ⏱ **The first build takes 10–20 minutes.** JitPack has to clone the Flutter
> SDK and compile the Dart dashboard to native code. This is normal. The log
> streams live — leave the page open.

**Check it worked:** the status turns into a green version badge. Click **Log**
and confirm it ends with:

```
==> Artifacts installed:
    ... stacker_debug-1.0.aar
    ... stacker_release-1.0.aar
    ... flutter_debug-1.0.aar
    ... flutter_release-1.0.aar
==> Done.
```

If it turns red, see [Troubleshooting](#troubleshooting).

### 3.3 Understand the version number

This surprises everyone, so it is worth reading once.

`flutter build aar` **always** stamps its output as Maven version `1.0`. That is
a Flutter toolchain behaviour and cannot be changed. So the dependency line
your users write is:

```gradle
debugImplementation 'com.stacker.stacker:stacker_debug:1.0'
```

The **git tag** selects which release they get, because JitPack builds one
immutable artifact set per tag. Pinning `v0.1.0` on the JitPack page pins the
build; the `1.0` string never changes.

---

## Step 4 — Publish to CocoaPods (native iOS)

Native iOS apps get prebuilt `.xcframework` binaries so their developers never
need the Flutter SDK. Unlike Android, you build and upload the artifact
yourself.

**Requires a Mac with Xcode.**

### 4.1 Build the framework bundle

```bash
cd /path/to/stacker
./scripts/build_ios_frameworks.sh 0.1.0
```

This takes a few minutes — it compiles the Dart dashboard to AOT machine code.

**What success looks like:**

```
==> Done
    file:   /path/to/stacker/dist/StackerInspector-iOS-XCFrameworks-0.1.0.zip
    size:    81M
    sha256: 3a42b278...
```

The file is ~81 MB. That is expected: it contains the Flutter engine for both
physical devices and the simulator. `dist/` is git-ignored, so the zip is never
committed.

### 4.2 Attach the zip to a GitHub Release

1. Go to `https://github.com/YOUR_USERNAME/stacker/releases/new`.
2. **Choose a tag:** pick the existing `v0.1.0`.
3. **Release title:** `v0.1.0`.
4. **Attach binaries:** drag in `dist/StackerInspector-iOS-XCFrameworks-0.1.0.zip`.
   Wait for the upload to finish — 81 MB takes a minute or two.
5. Press **Publish release**.

**Check it worked:** the download URL must resolve. This must print `200`:

```bash
curl -o /dev/null -s -w "%{http_code}\n" -L \
  https://github.com/YOUR_USERNAME/stacker/releases/download/v0.1.0/StackerInspector-iOS-XCFrameworks-0.1.0.zip
```

If it prints `404`, the filename in the URL does not match the uploaded asset
exactly — check for a typo or a version mismatch.

### 4.3 Validate the podspec

```bash
pod spec lint StackerInspector.podspec --allow-warnings
```

This downloads your zip and tries to build against it, so it takes a few
minutes. **Success looks like:**

```
StackerInspector.podspec passed validation.
```

> `--allow-warnings` is needed because CocoaPods warns about large vendored
> frameworks. That warning is expected here.

### 4.4 Choose how to distribute the pod

**Option A — Podspec URL (easiest, no account).** Commit the podspec and have
users point at it directly:

```bash
git add StackerInspector.podspec
git commit -m "Add native iOS podspec for 0.1.0"
git push
```

Users then write:

```ruby
pod 'StackerInspector', :podspec => 'https://raw.githubusercontent.com/YOUR_USERNAME/stacker/v0.1.0/StackerInspector.podspec'
```

**Option B — CocoaPods Trunk (users write just `pod 'StackerInspector'`).** Requires a
one-time registration:

```bash
pod trunk register you@example.com 'Your Name' --description='laptop'
```

Click the link in the confirmation email, then:

```bash
pod trunk push StackerInspector.podspec --allow-warnings
```

**Check it worked:** `pod search StackerInspector` finds it (allow ~10 minutes for the
CDN), or visit `https://cocoapods.org/pods/StackerInspector`.

> ⚠️ Trunk pushes are **permanent** — a published version cannot be deleted.
> The name `StackerInspector` is also globally unique across all of CocoaPods, so check
> `https://cocoapods.org/pods/StackerInspector` is free before pushing. Option A has
> neither constraint, which is why it is listed first.

---

## Step 5 — Verify all three

Do this from **throwaway projects**, not your real app. Installing from your
own working copy proves nothing — you want to prove a *stranger* can install it.

### Flutter

```bash
flutter create /tmp/verify_flutter && cd /tmp/verify_flutter
flutter pub add stacker_inspector
flutter pub get
```

Expect: resolves and downloads `stacker 0.1.0` from pub.dev.

### Native Android

Create an empty Android Studio project, then:

```gradle
// settings.gradle
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
        maven { url 'https://storage.googleapis.com/download.flutter.io' }
    }
}
```

```gradle
// app/build.gradle — needs compileSdk 36
dependencies {
    debugImplementation 'com.stacker.stacker:stacker_debug:1.0'
    debugImplementation 'com.stacker.stacker_host:flutter_debug:1.0'
}
```

```bash
./gradlew :app:assembleDebug
```

Expect: build succeeds, and running the app shows **two launcher icons** — the
app's own plus **Stacker**. Then confirm a release build has only one:

```bash
./gradlew :app:assembleRelease
```

### Native iOS

Create an empty Xcode project, then:

```ruby
# Podfile
platform :ios, '13.0'
target 'YourApp' do
  use_frameworks!
  pod 'StackerInspector', :podspec => 'https://raw.githubusercontent.com/YOUR_USERNAME/stacker/v0.1.0/StackerInspector.podspec'
end
```

```bash
pod install
```

Expect: downloads the 81 MB zip, then `open YourApp.xcworkspace` builds. Add
`StackerAutoAttach.enable()` under `#if DEBUG`, run on a simulator, and
**Device ▸ Shake** opens the dashboard.

---

## Releasing a new version later

Once the first release is out, subsequent ones are short.

```bash
# 1. Bump the version in three places — they must match.
#    pubspec.yaml        version: 0.2.0
#    ios/stacker_inspector.podspec s.version = '0.2.0'
#    StackerInspector.podspec     s.version = '0.2.0'  and the s.source URL's tag

# 2. Add a CHANGELOG.md entry. pub.dev scores you on this.

# 3. Commit and tag.
git add -A
git commit -m "Release 0.2.0"
git push
git tag v0.2.0
git push origin v0.2.0

# 4. pub.dev
flutter pub publish

# 5. JitPack — just visit the page and press "Get it" on the new tag.
#    https://jitpack.io/#YOUR_USERNAME/stacker

# 6. iOS
./scripts/build_ios_frameworks.sh 0.2.0
# then attach dist/StackerInspector-iOS-XCFrameworks-0.2.0.zip to the v0.2.0 release
```

> **Easy mistake:** forgetting to update the tag inside `StackerInspector.podspec`'s
> `s.source` URL. It would still point at the old release's zip, so iOS users
> silently get the previous version. `pod spec lint` catches this.

---

## Troubleshooting

### pub.dev

<details>
<summary><b>"Package has N warnings" and publish is blocked</b></summary>

Run `flutter pub publish --dry-run` and read each warning. Common ones:

- **Uncommitted changes** — commit first; pub prefers a clean tree.
- **Missing `example/`** — it exists in this repo; check `.pubignore` has not
  started excluding it.
- **Archive too large** — `.pubignore` is missing or broken. It must exclude
  `stacker_host/`.
</details>

<details>
<summary><b>"Version 0.1.0 already exists"</b></summary>

That version was already published and can never be reused. Bump to `0.1.1`.
This is exactly why Step 2.2 suggests a prerelease first.
</details>

### JitPack

<details>
<summary><b>Build fails with "flutter: command not found"</b></summary>

The SDK clone failed inside JitPack's container. Open
`scripts/jitpack_build.sh` and change `FLUTTER_VERSION` to a tag that exists
in the Flutter repository, then re-tag and rebuild.
</details>

<details>
<summary><b>Build times out</b></summary>

JitPack caps build duration and the AOT compile is slow. Retry first — the
Flutter SDK may be cached on the second attempt. If it keeps timing out, edit
the script to build fewer variants.
</details>

<details>
<summary><b>"No such file or directory: stacker_host"</b></summary>

The tag points at a commit from before the Flutter module existed. Tag a newer
commit.
</details>

<details>
<summary><b>Consumer error: "requires ... compile against version 36 or later"</b></summary>

Not a bug. The Flutter engine AAR sets `minCompileSdk=36`, so consuming apps
must use `compileSdk 36` and AGP 8.9+. This is documented in the README as a
hard requirement.
</details>

### CocoaPods

<details>
<summary><b>`pod spec lint` fails to download the source</b></summary>

The `s.source` URL is wrong or the release asset is not attached yet. Verify
with the `curl` command in Step 4.2 — it must return `200`.
</details>

<details>
<summary><b>"The `Stacker` pod name is already taken"</b></summary>

CocoaPods names are globally unique. Rename the pod in `StackerInspector.podspec`
(`s.name`) to something free, e.g. `StackerInspector`, and rename the file to
match.
</details>

<details>
<summary><b>Host app fails to launch with a Flutter engine error</b></summary>

Debug and Release Flutter artifacts are not interchangeable: the Release engine
runs AOT code, the Debug engine runs a JIT kernel snapshot. This podspec vends
the **Release** set for all configurations deliberately. If you swapped in the
Debug frameworks by hand, revert that.
</details>

---

## Quick reference

```bash
# Verify everything before releasing
flutter analyze && flutter test && flutter pub publish --dry-run

# Publish, in order
flutter pub publish                              # 1. pub.dev
git tag v0.1.0 && git push origin v0.1.0         # 2. tag → JitPack "Get it"
./scripts/build_ios_frameworks.sh 0.1.0          # 3. iOS zip → GitHub Release
pod spec lint StackerInspector.podspec --allow-warnings   #    then validate
```

| Channel | Dashboard |
|---|---|
| pub.dev | `https://pub.dev/packages/stacker_inspector` |
| JitPack | `https://jitpack.io/#YOUR_USERNAME/stacker` |
| GitHub Releases | `https://github.com/YOUR_USERNAME/stacker/releases` |
| CocoaPods | `https://cocoapods.org/pods/StackerInspector` *(Trunk only)* |
