// AudioBrain.swift
// Originally developed by Ashley Powell in May 2016.
// Retains Swift 2.2-era syntax

import Foundation
import AVFoundation

enum AudioBrainError: ErrorType, CustomStringConvertible {
    case InvalidConfiguration(String)
    case MissingAudio(String)
    case PlaybackFailed(String)
    case NoExercise

    var description: String {
        switch self {
        case .InvalidConfiguration(let message): return message
        case .MissingAudio(let name):
            return "Missing audio resource: \(name).wav or \(name).mp3."
        case .PlaybackFailed(let name):
            return "Unable to play audio resource: \(name)."
        case .NoExercise:
            return "Configure and start an exercise first."
        }
    }
}

class AudioBrain {
    // MARK: - User configuration

    var numberOfNotes = 2
    var stepsInWarmup = 4
    var stepsBetweenNotes = 1
    var stepsBetweenAnswers = 1
    var stepsBetweenNotesAndAnswers = 1
    var bpm = 78.0
    var keyNoteNum = 12                     // C = 1, B = 12.
    var chosenSyllableSet = Set<String>()
    var chosenOctaveSet = Set<Int>()

    let noteNames = ["C", "C#", "D", "D#", "E", "F",
                     "F#", "G", "G#", "A", "A#", "B"]

    // 1-based chromatic degrees, relative to the selected key.
    private let numbersFromSyllables: [String: Int] = [
        "Do": 1, "Ra": 2, "Re": 3, "Me": 4, "Mi": 5, "Fa": 6,
        "Se": 7, "So": 8, "Le": 9, "La": 10, "Te": 11, "Ti": 12
    ]

    // MARK: - Audio resources

    // The original recordings are arranged C1...B1, C2...B2, through C7...B7.
    // Derive the same filenames rather than maintaining 84 literal entries.
    private var testFiles: [String] {
        var files = [String]()
        for octave in 1...7 {
            for note in noteNames {
                files.append("note\(note)\(octave)")
            }
        }
        return files
    }

    private let solFiles = [
        "solDo", "solRa", "solRe", "solMe", "solMi", "solFa",
        "solSe", "solSo", "solLe", "solLa", "solTe", "solTi"
    ]

    private var chordFiles: [String] {
        return noteNames.map { "crdstgHSE\($0)Maj" }
    }

    // Zero-based semitone offsets for the original I-IV-V progression.
    private let warmupChordOffsets = [0, 5, 7]

    private enum AudioChannel {
        case Note, Chord, Answer
    }

    private var notePlayer: AVAudioPlayer?
    private var chordPlayer: AVAudioPlayer?
    private var answerPlayer: AVAudioPlayer?
    private var noteIsPaused = false
    private var chordIsPaused = false
    private var answerIsPaused = false

    // A new player is created for each recording, so retain the slider levels.
    var volume1: Float = 1.0 {
        didSet { notePlayer?.volume = volume1 }
    }
    var volume2: Float = 1.0 {
        didSet { chordPlayer?.volume = volume2 }
    }
    var volume3: Float = 1.0 {
        didSet { answerPlayer?.volume = volume3 }
    }

    // MARK: - Active exercise

    private struct ExerciseNote {
        let noteFileIndex: Int
        let answerFileIndex: Int
    }

    // Capture settings on Start so UI edits cannot alter a cycle halfway through.
    private struct Session {
        let keyIndex: Int
        let numberOfNotes: Int
        let warmupSteps: Int
        let noteGap: Int
        let answerGap: Int
        let answerDelay: Int
        let secondsPerBeat: Double

        var firstTestStep: Int { return warmupSteps + 1 }
        var lastTestStep: Int {
            return firstTestStep + (numberOfNotes - 1) * (noteGap + 1)
        }
        var firstAnswerStep: Int { return lastTestStep + answerDelay + 1 }
        var lastAnswerStep: Int {
            return firstAnswerStep + (numberOfNotes - 1) * (answerGap + 1)
        }
        var finalStep: Int { return lastAnswerStep + answerGap }
    }

    private var session: Session?
    private var selectedSyllables = [String]()
    private var noteIndexesBySyllable = [String: [Int]]()
    private var exerciseNotes = [ExerciseNote]()
    private(set) var currentStepPosition = 1
    private(set) var currentChord = ""

    var secondsPerBeat: Double { return session?.secondsPerBeat ?? 60.0 / 78.0 }

    func setup() throws {
        // A failed setup must not leave a previous session available to resume.
        stopAudio()
        session = nil
        exerciseNotes.removeAll()
        selectedSyllables.removeAll()
        noteIndexesBySyllable.removeAll()
        currentStepPosition = 1
        currentChord = ""

        guard bpm >= 1 && bpm <= 600 else {
            throw AudioBrainError.InvalidConfiguration("Enter a tempo from 1 to 600 BPM.")
        }
        guard keyNoteNum >= 1 && keyNoteNum <= 12 else {
            throw AudioBrainError.InvalidConfiguration("Select a valid musical key.")
        }
        guard numberOfNotes > 0 else {
            throw AudioBrainError.InvalidConfiguration("Choose at least one test note.")
        }
        guard stepsInWarmup >= 0 && stepsBetweenNotes >= 0 &&
              stepsBetweenAnswers >= 0 && stepsBetweenNotesAndAnswers >= 0 else {
            throw AudioBrainError.InvalidConfiguration("Timing intervals cannot be negative.")
        }
        guard !chosenSyllableSet.isEmpty && !chosenOctaveSet.isEmpty else {
            throw AudioBrainError.InvalidConfiguration("Select at least one syllable and octave.")
        }

        for octave in chosenOctaveSet {
            guard octave >= 1 && octave <= 7 else {
                throw AudioBrainError.InvalidConfiguration("Recorded notes cover octaves 1 through 7.")
            }
        }

        // Sorting makes the candidate lists easy to inspect without changing the
        // uniform probability of selecting any syllable or octave.
        let octaves = chosenOctaveSet.sort()
        selectedSyllables = chosenSyllableSet.sort()

        for syllable in selectedSyllables {
            guard let degree = numbersFromSyllables[syllable] else {
                throw AudioBrainError.InvalidConfiguration("Unknown solfege syllable: \(syllable).")
            }

            // Convert key + relative degree to a zero-based pitch class (0...11).
            // Preserve the original behavior: wrap within the selected absolute
            // octave, rather than carrying into the next octave at B -> C.
            let pitchClass = (keyNoteNum - 1 + degree - 1) % 12
            noteIndexesBySyllable[syllable] = octaves.map {
                pitchClass + ($0 - 1) * 12
            }
        }

        session = Session(
            keyIndex: keyNoteNum - 1,
            numberOfNotes: numberOfNotes,
            warmupSteps: stepsInWarmup,
            noteGap: stepsBetweenNotes,
            answerGap: stepsBetweenAnswers,
            answerDelay: stepsBetweenNotesAndAnswers,
            secondsPerBeat: 60.0 / bpm
        )
    }

    private func randomize(numberOfNotes: Int) throws {
        exerciseNotes.removeAll()

        // Select a syllable and then one of its allowed octave recordings.
        // Store each pitch with its answer so the two cannot become misaligned.
        for _ in 0..<numberOfNotes {
            let syllableIndex = Int(arc4random_uniform(UInt32(selectedSyllables.count)))
            let syllable = selectedSyllables[syllableIndex]
            guard let noteIndexes = noteIndexesBySyllable[syllable],
                  let degree = numbersFromSyllables[syllable] where !noteIndexes.isEmpty else {
                throw AudioBrainError.InvalidConfiguration("No recordings configured for \(syllable).")
            }
            let octaveIndex = Int(arc4random_uniform(UInt32(noteIndexes.count)))
            exerciseNotes.append(ExerciseNote(
                noteFileIndex: noteIndexes[octaveIndex],
                answerFileIndex: degree - 1
            ))
        }
    }

    // MARK: - Beat-driven sequencing

    // Each call advances one timer step. Gap settings count SILENT steps between
    // events: a gap of 1 means notes occur every 2 steps. Return the step just
    // processed so the UI displays it, rather than the next scheduled step.
    func sequence() throws -> Int {
        guard let session = session else { throw AudioBrainError.NoExercise }
        let step = currentStepPosition

        if step == 1 {
            try randomize(session.numberOfNotes)
        }

        if step < session.firstTestStep {
            // End the warmup on the tonic. Longer warmups repeat I-IV-V safely;
            // the original four-step warmup remains I, IV, V, I.
            let offset = step == session.warmupSteps
                ? 0 : warmupChordOffsets[(step - 1) % warmupChordOffsets.count]
            let chordIndex = (session.keyIndex + offset) % 12
            try playChords(chordIndex)
        } else if step < session.firstAnswerStep {
            let elapsed = step - session.firstTestStep
            let interval = session.noteGap + 1
            let noteIndex = elapsed / interval
            if elapsed % interval == 0 && noteIndex < exerciseNotes.count {
                try playRandomTestNote(exerciseNotes[noteIndex].noteFileIndex)
            }
        } else {
            let elapsed = step - session.firstAnswerStep
            let interval = session.answerGap + 1
            let noteIndex = elapsed / interval
            if elapsed % interval == 0 && noteIndex < exerciseNotes.count {
                let note = exerciseNotes[noteIndex]
                try playRandomTestNote(note.noteFileIndex)
                try playAnswer(note.answerFileIndex)
            }
        }

        currentStepPosition = step == session.finalStep ? 1 : step + 1
        return step
    }

    // MARK: - Playback

    func playRandomTestNote(index: Int) throws {
        let files = testFiles
        guard index >= 0 && index < files.count else {
            throw AudioBrainError.InvalidConfiguration("Invalid note recording index.")
        }
        try playFile(files[index], channel: .Note)
    }

    private func playChords(index: Int) throws {
        let files = chordFiles
        try playFile(files[index], channel: .Chord)
        currentChord = noteNames[index] + " major"
    }

    private func playAnswer(index: Int) throws {
        try playFile(solFiles[index], channel: .Answer)
    }

    // Used by the original individual audio buttons in ViewController.
    func playNoteFile(name: String) throws {
        try playFile(name, channel: .Note)
    }

    private func playFile(name: String, channel: AudioChannel) throws {
        // Try each supported extension once. A missing MP3 must not recurse.
        let bundle = NSBundle.mainBundle()
        guard let path = bundle.pathForResource(name, ofType: "wav") ??
                         bundle.pathForResource(name, ofType: "mp3") else {
            throw AudioBrainError.MissingAudio(name)
        }

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOfURL: NSURL(fileURLWithPath: path))
        } catch {
            throw AudioBrainError.PlaybackFailed(name)
        }

        player.numberOfLoops = 0
        switch channel {
        case .Note:
            notePlayer?.stop()
            noteIsPaused = false
            player.volume = volume1
            notePlayer = player
        case .Chord:
            chordPlayer?.stop()
            chordIsPaused = false
            player.volume = volume2
            chordPlayer = player
        case .Answer:
            answerPlayer?.stop()
            answerIsPaused = false
            player.volume = volume3
            answerPlayer = player
        }

        guard player.play() else { throw AudioBrainError.PlaybackFailed(name) }
    }

    func pauseAudio() {
        // Retain which channels were playing, including at time zero. Repeated
        // Pause presses must not discard the state needed by Resume.
        noteIsPaused = noteIsPaused || (notePlayer?.playing ?? false)
        chordIsPaused = chordIsPaused || (chordPlayer?.playing ?? false)
        answerIsPaused = answerIsPaused || (answerPlayer?.playing ?? false)
        notePlayer?.pause()
        chordPlayer?.pause()
        answerPlayer?.pause()
    }

    func resumeAudio() throws {
        // Do not restart recordings that have already finished or been stopped.
        let channels = [(notePlayer, noteIsPaused), (chordPlayer, chordIsPaused),
                        (answerPlayer, answerIsPaused)]
        for (player, wasPaused) in channels {
            if let player = player where wasPaused {
                guard player.play() else {
                    throw AudioBrainError.PlaybackFailed("paused recording")
                }
            }
        }
        noteIsPaused = false
        chordIsPaused = false
        answerIsPaused = false
    }

    func stopAudio() {
        notePlayer?.stop()
        chordPlayer?.stop()
        answerPlayer?.stop()
        notePlayer = nil
        chordPlayer = nil
        answerPlayer = nil
        noteIsPaused = false
        chordIsPaused = false
        answerIsPaused = false
    }

    func stopExercise() {
        stopAudio()
        session = nil
        exerciseNotes.removeAll()
        currentStepPosition = 1
        currentChord = ""
    }
}
