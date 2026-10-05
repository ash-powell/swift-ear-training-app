// ViewController.swift
// Originally developed by Ashley Powell in May 2016.

import UIKit

class ViewController: UIViewController, UITextFieldDelegate {
    private let audioBrain = AudioBrain()
    private var timer: NSTimer?
    private var exerciseIsPaused = false
    private let selectedColor = UIColor.blackColor()
    private let deselectedColor = UIColor.blackColor().colorWithAlphaComponent(0.5)

    // MARK: - Storyboard connections

    @IBOutlet weak var bpm: UITextField!
    @IBOutlet weak var keyButton: UIButton!
    @IBOutlet weak var numberOfNotesDisplay: UILabel!
    @IBOutlet weak var numberNotesStepper: UIStepper!
    @IBOutlet weak var warmupStepControl: UIStepper!
    @IBOutlet weak var warmupStepDisplay: UILabel!
    @IBOutlet weak var stepsBetweenNotesDisplay: UILabel!
    @IBOutlet weak var stepsBetweenNotesControl: UIStepper!
    @IBOutlet weak var stepsBetweenAnswersDisplay: UILabel!
    @IBOutlet weak var stepsBetweenAnswersControl: UIStepper!
    @IBOutlet weak var stepsBetweenNotesAndAnswersDisplay: UILabel!
    @IBOutlet weak var stepsBetweenNotesAndAnswersControl: UIStepper!
    @IBOutlet weak var volumeController1: UISlider!
    @IBOutlet weak var volumeController2: UISlider!
    @IBOutlet weak var volumeController3: UISlider!
    @IBOutlet weak var stepPositionLabel: UILabel!
    @IBOutlet weak var testLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        bpm.delegate = self
        bpm.text = String(audioBrain.bpm)
        updateKeyTitle()

        numberNotesStepper.minimumValue = 1
        warmupStepControl.minimumValue = 0
        stepsBetweenNotesControl.minimumValue = 0
        stepsBetweenAnswersControl.minimumValue = 0
        stepsBetweenNotesAndAnswersControl.minimumValue = 0

        numberNotesStepper.value = Double(audioBrain.numberOfNotes)
        warmupStepControl.value = Double(audioBrain.stepsInWarmup)
        stepsBetweenNotesControl.value = Double(audioBrain.stepsBetweenNotes)
        stepsBetweenAnswersControl.value = Double(audioBrain.stepsBetweenAnswers)
        stepsBetweenNotesAndAnswersControl.value = Double(audioBrain.stepsBetweenNotesAndAnswers)

        numberOfNotesDisplay.text = String(audioBrain.numberOfNotes)
        warmupStepDisplay.text = String(audioBrain.stepsInWarmup)
        stepsBetweenNotesDisplay.text = String(audioBrain.stepsBetweenNotes)
        stepsBetweenAnswersDisplay.text = String(audioBrain.stepsBetweenAnswers)
        stepsBetweenNotesAndAnswersDisplay.text = String(audioBrain.stepsBetweenNotesAndAnswers)

        audioBrain.volume1 = volumeController1.value
        audioBrain.volume2 = volumeController2.value
        audioBrain.volume3 = volumeController3.value
        resetStatusLabels()
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        // NSTimer retains its target until invalidated.
        endExercise()
    }

    deinit {
        timer?.invalidate()
    }

    func textFieldShouldReturn(textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: - Exercise configuration

    @IBAction func keyChange(sender: UIButton) {
        audioBrain.keyNoteNum = audioBrain.keyNoteNum % 12 + 1
        updateKeyTitle()
    }

    private func updateKeyTitle() {
        let note = audioBrain.noteNames[audioBrain.keyNoteNum - 1]
        keyButton.setTitle("Key: \(note)", forState: .Normal)
    }

    @IBAction func numberNotesSet(sender: UIStepper) {
        audioBrain.numberOfNotes = Int(sender.value)
        numberOfNotesDisplay.text = String(audioBrain.numberOfNotes)
    }

    @IBAction func warmupStepSetter(sender: UIStepper) {
        audioBrain.stepsInWarmup = Int(sender.value)
        warmupStepDisplay.text = String(audioBrain.stepsInWarmup)
    }

    @IBAction func stepsBetweenNotesSet(sender: UIStepper) {
        audioBrain.stepsBetweenNotes = Int(sender.value)
        stepsBetweenNotesDisplay.text = String(audioBrain.stepsBetweenNotes)
    }

    @IBAction func stepsBetweenAnswersSet(sender: UIStepper) {
        audioBrain.stepsBetweenAnswers = Int(sender.value)
        stepsBetweenAnswersDisplay.text = String(audioBrain.stepsBetweenAnswers)
    }

    @IBAction func stepsBetweenNotesAndAnswersSet(sender: UIStepper) {
        audioBrain.stepsBetweenNotesAndAnswers = Int(sender.value)
        stepsBetweenNotesAndAnswersDisplay.text = String(audioBrain.stepsBetweenNotesAndAnswers)
    }

    @IBAction func solPressed(sender: UIButton) {
        guard let syllable = sender.currentTitle else { return }
        if audioBrain.chosenSyllableSet.contains(syllable) {
            audioBrain.chosenSyllableSet.remove(syllable)
            setSelectionAppearance(sender, selected: false)
        } else {
            audioBrain.chosenSyllableSet.insert(syllable)
            setSelectionAppearance(sender, selected: true)
        }
    }

    @IBAction func octavePressed(sender: UIButton) {
        guard let title = sender.currentTitle, let octave = Int(title) else { return }
        if audioBrain.chosenOctaveSet.contains(octave) {
            audioBrain.chosenOctaveSet.remove(octave)
            setSelectionAppearance(sender, selected: false)
        } else {
            audioBrain.chosenOctaveSet.insert(octave)
            setSelectionAppearance(sender, selected: true)
        }
    }

    private func setSelectionAppearance(button: UIButton, selected: Bool) {
        // Selection comes from the model; appearance reflects that decision.
        button.alpha = selected ? 1.0 : 0.5
        button.backgroundColor = selected ? selectedColor : deselectedColor
    }

    // MARK: - Playback controls

    // Historical action name retained for the original Start button connection.
    @IBAction func randomFile(sender: UIButton) {
        guard let text = bpm.text, let tempo = Double(text)
            where tempo >= 1 && tempo <= 600 else {
            showError("Enter a tempo from 1 to 600 BPM.")
            return
        }

        endExercise()
        audioBrain.bpm = tempo
        do {
            try audioBrain.setup()
            startTimer()
        } catch {
            endExercise()
            showError(String(error))
        }
    }

    private func startTimer() {
        // Exactly one timer drives the sequence, including after a restart.
        timer?.invalidate()
        timer = NSTimer.scheduledTimerWithTimeInterval(
            audioBrain.secondsPerBeat,
            target: self,
            selector: #selector(ViewController.incrementBeat),
            userInfo: nil,
            repeats: true
        )
    }

    // Must remain visible to Objective-C because NSTimer invokes its selector.
    @objc func incrementBeat() {
        do {
            let playedStep = try audioBrain.sequence()
            stepPositionLabel.text = String(playedStep)
            testLabel.text = audioBrain.currentChord.isEmpty
                ? "Chord: —" : "Chord: \(audioBrain.currentChord)"
        } catch {
            endExercise()
            showError(String(error))
        }
    }

    @IBAction func pauseAudio(sender: AnyObject) {
        // Freeze both scheduling and all three audio channels.
        if timer != nil {
            timer?.invalidate()
            timer = nil
            exerciseIsPaused = true
        }
        audioBrain.pauseAudio()
    }

    @IBAction func playAudio(sender: AnyObject) {
        do {
            try audioBrain.resumeAudio()
            if exerciseIsPaused {
                exerciseIsPaused = false
                startTimer()
            }
        } catch {
            endExercise()
            showError(String(error))
        }
    }

    @IBAction func stopAudio(sender: AnyObject) {
        endExercise()
    }

    private func endExercise() {
        timer?.invalidate()
        timer = nil
        exerciseIsPaused = false
        audioBrain.stopExercise()
        resetStatusLabels()
    }

    private func resetStatusLabels() {
        stepPositionLabel.text = "—"
        testLabel.text = "Chord: —"
    }

    @IBAction func changeVolume1(sender: UISlider) {
        audioBrain.volume1 = sender.value
    }

    @IBAction func changeVolume2(sender: AnyObject) {
        guard let slider = sender as? UISlider else { return }
        audioBrain.volume2 = slider.value
    }

    @IBAction func changeVolume3(sender: AnyObject) {
        guard let slider = sender as? UISlider else { return }
        audioBrain.volume3 = slider.value
    }

    @IBAction func buttonPress(sender: AnyObject) {
        guard let button = sender as? UIButton, let name = button.currentTitle else { return }
        do {
            try audioBrain.playNoteFile(name)
        } catch {
            endExercise()
            showError(String(error))
        }
    }

    private func showError(message: String) {
        // Avoid presenting multiple alerts if the user presses a control again.
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Ear Trainer", message: message,
                                      preferredStyle: .Alert)
        alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
        presentViewController(alert, animated: true, completion: nil)
    }
}
