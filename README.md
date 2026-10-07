# iOS Contextual Ear Trainer

## What the app does
The app generates randomized contextual ear training exercises within a configurable key center. It establishes the key with a chord progression, plays test notes, then plays solfege answers after a configurable delay. Further discussion of ear training and how the app works from a user point of view follows here after a brief discussion of the code.

## What the code does

The challenge is how to map a simple collection of 84 mp3 files, each contianing a different piano note, to 1,008 key/syllable/octave combinations required to create randomized ear training exercises in any key. The same recorded pitch can represent different solfege syllables in different keys, so the engine tracks both the absolute pitch and its role within the established tonal context. For example, b4 is "mi" in the key of G major, but "ti" in C major.

To see this in the code, start with setup() in AudioBrain.swift to see how the recording mappings are constructed, then follow randomize() to see how those mappings produce exercises. 

AudioBrain.swift handles the musical mappings, random note generation, exercise sequence, and audio playback. 
ViewController.swift connects the UIKit controls to that logic and manages the timer.

To find a recording, the engine combines the selected key with the syllable's chromatic offset, then places that pitch in an allowed octave:

```swift
let pitchClass = (keyNoteNum - 1 + degree - 1) % 12
let recordingIndex = pitchClass + (octave - 1) * 12
```

The recordings are ordered chromatically from C1 through B7. Octave selections refer to those absolute recorded octaves; a pitch-class wrap does not move the note into the next octave.

For each test note, the engine randomly selects an allowed syllable and one of its allowed octave recordings. It keeps the recording index and answer index together so the correct answer remains attached to the note. Repeated notes are allowed.

A beat-driven sequence controls the warmup, test notes, answer delay, and answer playback. Timing gaps count silent timer steps between events. Notes, chords, and answers use separate audio players so they can overlap and have independent volume levels.

I developed this iPhone app in Swift in 2016, and the files retain Swift 2 era syntax. The original storyboard, audio recordings, and Xcode project are not included.


## How the app works from a user's perspective
The focus is contextual ear training, also called functional ear training: learning to hear a note's identity and function within a key.

1. Select a key, the syllables to practice, and the allowed octaves.
2. Choose the number of notes, tempo, and timing settings.
3. Start the exercise. The default warmup plays I-IV-V-I in the selected key.
4. Listen to the randomly generated notes and try to identify their syllables.
5. After the chosen delay, the app replays each note together with its solfege answer.

The cycle repeats with a new set of random notes. Answers are provided as audio for self-checking; the app does not record or grade the listener's responses at this time.

## Settings

- Musical key
- Allowed chromatic solfege syllables: Do, Ra, Re, Me, Mi, Fa, Se, So, Le, La, Te, and Ti
- Allowed octaves
- Number of test notes
- Tempo and warmup length
- Spacing between test notes, delay before answers, and spacing between answers
- Independent volume levels for notes, chords, and answers

Once a key is established, each scale degree has its own character. Do is the tonal center; Ti is the leading tone. The app uses movable-Do solfege, so the syllable associated with a pitch changes with the key. For example, B is Mi in G major, but Ti in C major.

The chord warmup gives the listener that context before the test notes begin. The exercise is to recognize the notes by their relationship to the established key.

The user can start with a small group of syllables and expand the selection as recognition improves.

## Why contextual ear training

Contextual ear training teaches you to recognize each note’s character and function within a musical key. This can be more useful for understanding actual music than practicing isolated intervals, because it develops recognition of tonal relationships rather than just the distance between two pitches.



