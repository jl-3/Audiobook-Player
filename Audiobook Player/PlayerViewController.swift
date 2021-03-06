//
//  PlayerViewController.swift
//  Audiobook Player
//
//  Created by Gianni Carlo on 7/5/16.
//  Copyright © 2016 Tortuga Power. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer
import Chameleon
import MBProgressHUD
import StoreKit

class PlayerViewController: UIViewController {
    @IBOutlet weak var authorLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var forwardButton: UIButton!
    @IBOutlet weak var rewindButton: UIButton!
    
    @IBOutlet weak var maxTimeLabel: UILabel!
    @IBOutlet weak var currentTimeLabel: UILabel!
    
    @IBOutlet weak var timeSeparator: UILabel!
    var audioPlayer:AVAudioPlayer?
    
    @IBOutlet weak var leftVerticalView: UIView!
    @IBOutlet weak var sliderView: UISlider!
    
    @IBOutlet weak var percentageLabel: UILabel!
    
    @IBOutlet weak var chaptersButton: UIButton!
    @IBOutlet weak var speedButton: UIButton!
    @IBOutlet weak var sleepButton: UIButton!
    
    @IBOutlet weak var sleepTimerWidthConstraint: NSLayoutConstraint!
    
    
    //keep in memory current Documents folder
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    
    var namesArray:[String]!
    var fileURL:URL!
    
    //keep in memory images to toggle play/pause
    let playImage = UIImage(named: "playButton")
    let pauseImage = UIImage(named: "pauseButton")
    
    //current item to play
    var playerItem:AVPlayerItem!
    
    //timer to update labels about time
    var timer:Timer!
    
    //timer to update sleep time
    var sleepTimer:Timer!
    
    //book identifier for `NSUserDefaults`
    var identifier:String!
    
    //chapters
    var chapterArray:[Chapter] = []
    var currentChapter:Chapter?
    
    //speed
    var currentSpeed:Float = 1.0
    
    //MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //set UI colors
        let colors:[UIColor] = [
            UIColor.flatGrayColorDark(),
            UIColor.flatSkyBlueColorDark()
        ]
        self.view.backgroundColor = GradientColor(.radial, frame: view.frame, colors: colors)
        self.leftVerticalView.backgroundColor = UIColor.flatRed()
        self.maxTimeLabel.textColor = UIColor.flatWhiteColorDark()
        self.authorLabel.textColor = UIColor.flatWhiteColorDark()
        self.timeSeparator.textColor = UIColor.flatWhiteColorDark()
        self.chaptersButton.setTitleColor(UIColor.flatGray(), for: .disabled)
        self.speedButton.setTitleColor(UIColor.flatGray(), for: .disabled)
        self.sleepButton.tintColor = UIColor.white
        
        self.setStatusBarStyle(UIStatusBarStyleContrast)
        
        //register for appDelegate requestReview notifications
        NotificationCenter.default.addObserver(self, selector: #selector(self.requestReview), name: Notification.Name.AudiobookPlayer.requestReview, object: nil)
        
        //load book metadata
        self.titleLabel.text = AVMetadataItem.metadataItems(from: self.playerItem.asset.metadata, withKey: AVMetadataCommonKeyTitle, keySpace: AVMetadataKeySpaceCommon).first?.value?.copy(with: nil) as? String ?? self.fileURL.lastPathComponent
        
        self.authorLabel.text = AVMetadataItem.metadataItems(from: self.playerItem.asset.metadata, withKey: AVMetadataCommonKeyArtist, keySpace: AVMetadataKeySpaceCommon).first?.value?.copy(with: nil) as? String ?? "Unknown Author"
      
        var defaultImage:UIImage!
        if let artwork = AVMetadataItem.metadataItems(from: self.playerItem.asset.metadata, withKey: AVMetadataCommonKeyArtwork, keySpace: AVMetadataKeySpaceCommon).first?.value?.copy(with: nil) as? Data {
        defaultImage = UIImage(data: artwork)
        }else{
          defaultImage = UIImage()
        }

        //set initial state for slider
        self.sliderView.setThumbImage(UIImage(), for: UIControlState())
        self.sliderView.tintColor = UIColor.flatLimeColorDark()
        self.sliderView.maximumValue = 100
        self.sliderView.value = 0
        
        self.percentageLabel.text = ""
        
        MBProgressHUD.showAdded(to: self.view, animated: true)
        
        //load data on background thread
        DispatchQueue.global().async {
            
            let mediaArtwork = MPMediaItemArtwork(image: defaultImage)
            
            //try loading the data of the book
            guard let data = FileManager.default.contents(atPath: self.fileURL.path) else {
                //show error on main thread
                DispatchQueue.main.async(execute: {
                    MBProgressHUD.hide(for: self.view, animated: true)
                    self.showAlert(nil, message: "Problem loading mp3 data", style: .alert)
                })
                
                return
            }
            
            //try loading the player
            self.audioPlayer = try? AVAudioPlayer(data: data)
            
            guard let audioplayer = self.audioPlayer else {
                //show error on main thread
                DispatchQueue.main.async(execute: {
                    MBProgressHUD.hide(for: self.view, animated: true)
                    self.showAlert(nil, message: "Problem loading player", style: .alert)
                })
                return
            }
            
            audioplayer.delegate = self
            
            //try loading chapters
            var chapterIndex = 1
            
            let locales = self.playerItem.asset.availableChapterLocales
            for locale in locales {
                let chapters = self.playerItem.asset.chapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [AVMetadataCommonKeyArtwork])
                
                for chapterMetadata in chapters {
                    
                    let chapter = Chapter(title: AVMetadataItem.metadataItems(from: chapterMetadata.items, withKey: AVMetadataCommonKeyTitle, keySpace: AVMetadataKeySpaceCommon).first?.value?.copy(with: nil) as? String ?? "Chapter \(chapterIndex)",
                                     start: Int(CMTimeGetSeconds(chapterMetadata.timeRange.start)),
                                     duration: Int(CMTimeGetSeconds(chapterMetadata.timeRange.duration)),
                                     index: chapterIndex)

                    if Int(audioplayer.currentTime) >= chapter.start {
                        self.currentChapter = chapter
                    }
                    
                    self.chapterArray.append(chapter)
                    chapterIndex = chapterIndex + 1
                }
                
            }
            
            //set percentage label to stored value
            let currentPercentage = UserDefaults.standard.string(forKey: self.identifier+"_percentage") ?? "0%"
            self.percentageLabel.text = currentPercentage
            
            //currentChapter is not reliable because of currentTime is not ready, set to blank
            if self.chapterArray.count > 0 {
                self.percentageLabel.text = ""
            }
            
            
            //update UI on main thread
            DispatchQueue.main.async(execute: {
                
                //set smart speed
                let speed = UserDefaults.standard.float(forKey: self.identifier+"_speed")
                self.currentSpeed = speed > 0 ? speed : 1.0
                self.speedButton.setTitle("Speed \(String(self.currentSpeed))x", for: UIControlState())
                
                //enable/disable chapters button
                self.chaptersButton.isEnabled = self.chapterArray.count > 0
                
                //set book metadata for lockscreen and control center
                MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                    MPMediaItemPropertyTitle: self.titleLabel.text ?? "Unknown Book",
                    MPMediaItemPropertyArtist: self.authorLabel.text ?? "Unknown Author",
                    MPMediaItemPropertyPlaybackDuration: audioplayer.duration,
                    MPMediaItemPropertyArtwork: mediaArtwork
                ]
                
                //get stored value for current time of book
                let currentTime = UserDefaults.standard.integer(forKey: self.identifier)
                
                //update UI if needed and set player to stored time
                if currentTime > 0 {
                    let formattedCurrentTime = self.formatTime(currentTime)
                    self.currentTimeLabel.text = formattedCurrentTime
                    
                    audioplayer.currentTime = TimeInterval(currentTime)
                }
                
                //update max duration label of book
                let maxDuration = Int(audioplayer.duration)
                self.maxTimeLabel.text = self.formatTime(maxDuration)
                self.sliderView.value = Float(currentTime)
                self.updateCurrentChapter()
                
                //set speed for player
                audioplayer.enableRate = true
                audioplayer.rate = self.currentSpeed
                
                //play audio automatically
                if let rootVC = self.navigationController?.viewControllers.first as? ListBooksViewController {
                    //only if the book isn't finished
                    if currentTime != maxDuration {
                        rootVC.didPressPlay(self.playButton)
                    }
                }
                
                MBProgressHUD.hide(for: self.view, animated: true)
            })
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        //hide navigation bar for this controller
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    //Resize sleep button on orientation transition
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { (context) in
            let orientation = UIApplication.shared.statusBarOrientation
            
            if orientation.isLandscape {
                self.sleepTimerWidthConstraint.constant = 20
            } else {
                self.sleepTimerWidthConstraint.constant = 30
            }
            
        })
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        //don't do anything special for other segues that weren't identified beforehand
        guard let identifier = segue.identifier else {
            return
        }
        
        //set every modal to preserve current view contaxt
        let vc = segue.destination
        vc.modalPresentationStyle = .overCurrentContext
        
        switch identifier {
        case "showChapterSegue":
            let chapterVC = vc as! ChaptersViewController
            chapterVC.chapterArray = self.chapterArray
            chapterVC.currentChapter = self.currentChapter
        case "showSpeedSegue":
            let speedVC = vc as! SpeedViewController
            speedVC.currentSpeed = self.currentSpeed
            break
        default:
            break
        }
    }
    
    @IBAction func didSelectChapter(_ segue:UIStoryboardSegue){
        
        guard let audioplayer = self.audioPlayer else {
            return
        }
        let vc = segue.source as! ChaptersViewController
        audioplayer.currentTime = TimeInterval(vc.currentChapter.start)
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioplayer.currentTime
        
        self.updateTimer()
    }
    
    @IBAction func didSelectSpeed(_ segue:UIStoryboardSegue){
        
        guard let audioplayer = self.audioPlayer else {
            return
        }
        let vc = segue.source as! SpeedViewController
        self.currentSpeed = vc.currentSpeed
        
        UserDefaults.standard.set(self.currentSpeed, forKey: self.identifier+"_speed")
        self.speedButton.setTitle("Speed \(String(self.currentSpeed))x", for: UIControlState())
        audioplayer.rate = self.currentSpeed
    }
    
    @IBAction func didSelectAction(_ segue:UIStoryboardSegue){
        
        guard let audioplayer = self.audioPlayer else {
            return
        }
        
        if audioplayer.isPlaying {
            self.playPressed(self.playButton)
        }
        
        let vc = segue.source as! MoreViewController
        guard let action = vc.selectedAction else {
            return
        }
        
        switch action.rawValue {
        case MoreAction.jumpToStart.rawValue:
            audioplayer.currentTime = 0
            break
        case MoreAction.markFinished.rawValue:
            audioplayer.currentTime = audioplayer.duration
            break
        default:
            break
        }
        
        self.updateTimer()
    }
    
    @IBAction func didPressSleepTimer(_ sender: UIButton) {
        
        var alertTitle:String? = nil
        if self.sleepTimer != nil && self.sleepTimer.isValid {
            alertTitle = " "
        }
        
        let alert = UIAlertController(title: alertTitle, message: nil, preferredStyle: .actionSheet)
        
        
        alert.addAction(UIAlertAction(title: "Off", style: .default, handler: { action in
            self.sleep(in: nil)
        }))
        
        alert.addAction(UIAlertAction(title: "In 5 Minutes", style: .default, handler: { action in
            self.sleep(in: 300)
        }))
        
        alert.addAction(UIAlertAction(title: "In 10 Minutes", style: .default, handler: { action in
            self.sleep(in: 600)
        }))
        alert.addAction(UIAlertAction(title: "In 15 Minutes", style: .default, handler: { action in
            self.sleep(in: 900)
        }))
        alert.addAction(UIAlertAction(title: "In 30 Minutes", style: .default, handler: { action in
            self.sleep(in: 1800)
        }))
        alert.addAction(UIAlertAction(title: "In 45 Minutes", style: .default, handler: { action in
            self.sleep(in: 2700)
        }))
        alert.addAction(UIAlertAction(title: "In One Hour", style: .default, handler: { action in
            self.sleep(in: 3600)
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        alert.popoverPresentationController?.sourceView = self.view
        alert.popoverPresentationController?.sourceRect = CGRect(x: Double(self.view.bounds.size.width / 2.0), y: Double(self.view.bounds.size.height-45), width: 1.0, height: 1.0)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func sleep(in seconds:Int?) {
        UserDefaults.standard.set(seconds, forKey: "sleep_timer")
        
        guard seconds != nil else {
            self.sleepButton.tintColor = UIColor.white
            //kill timer
            if self.sleepTimer != nil {
                self.sleepTimer.invalidate()
            }
            return
        }
        
        self.sleepButton.tintColor = UIColor.flatLimeColorDark()
        
        //create timer if needed
        if self.sleepTimer == nil || (self.sleepTimer != nil && !self.sleepTimer.isValid) {
            self.sleepTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateSleepTimer), userInfo: nil, repeats: true)
            RunLoop.main.add(self.sleepTimer, forMode: RunLoopMode.commonModes)
        }
    }
    
    func updateSleepTimer(){
        guard let audioplayer = self.audioPlayer else {
            //kill timer
            if self.sleepTimer != nil {
                self.sleepTimer.invalidate()
            }
            return
        }
        
        let currentTime = UserDefaults.standard.integer(forKey: "sleep_timer")
        
        var newTime:Int? = currentTime - 1
        
        if let alertVC = self.presentedViewController, alertVC is UIAlertController {
            alertVC.title = "Time: " + self.formatTime(newTime!)
        }
        
        if newTime! <= 0 {
            newTime = nil
            //stop audiobook
            if self.sleepTimer != nil && self.sleepTimer.isValid {
                self.sleepTimer.invalidate()
            }
            
            if audioplayer.isPlaying {
                self.playPressed(self.playButton)
            }
        }
        UserDefaults.standard.set(newTime , forKey: "sleep_timer")
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    override var preferredStatusBarUpdateAnimation : UIStatusBarAnimation {
        return .slide
    }
}

extension PlayerViewController: AVAudioPlayerDelegate {
    
    //skip time forward
    @IBAction func forwardPressed(_ sender: UIButton) {
        guard let audioplayer = self.audioPlayer else {
            return
        }
        let time = audioplayer.currentTime
        audioplayer.currentTime = time + 30
        //update time on lockscreen and control center
        MPNowPlayingInfoCenter.default().nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioplayer.currentTime
        //trigger timer event
        self.updateTimer()
    }
    
    //skip time backwards
    @IBAction func rewindPressed(_ sender: UIButton) {
        guard let audioplayer = self.audioPlayer else {
            return
        }
        
        let time = audioplayer.currentTime
        audioplayer.currentTime = time - 30
        //update time on lockscreen and control center
        MPNowPlayingInfoCenter.default().nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioplayer.currentTime
        //trigger timer event
        self.updateTimer()
    }
    
    //toggle play/pause of book
    @IBAction func playPressed(_ sender: UIButton) {
        guard let audioplayer = self.audioPlayer else {
            return
        }
        
        //pause player if it's playing
        if audioplayer.isPlaying {
            //invalidate timer if needed
            if self.timer != nil {
                self.timer.invalidate()
            }
            
            //set pause state on player and control center
            audioplayer.stop()
            MPNowPlayingInfoCenter.default().nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackRate] = 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioplayer.currentTime
            try! AVAudioSession.sharedInstance().setActive(false)
            
            //update image for play button
            self.playButton.setImage(self.playImage, for: UIControlState())
            self.sleep(in: nil)
            return
        }
        
        try! AVAudioSession.sharedInstance().setActive(true)
        
        //if book is completed, reset to start
        if audioplayer.duration == audioplayer.currentTime {
            audioplayer.currentTime = 0
        }
        
        //create timer if needed
        if self.timer == nil || (self.timer != nil && !self.timer.isValid) {
            self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateTimer), userInfo: nil, repeats: true)
            RunLoop.main.add(self.timer, forMode: RunLoopMode.commonModes)
        }
        
        //set play state on player and control center
        audioplayer.play()
        MPNowPlayingInfoCenter.default().nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackRate] = 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioplayer.currentTime
        
        //update image for play button
        self.playButton.setImage(self.pauseImage, for: UIControlState())
    }
    
    //timer callback (called every second)
    func updateTimer() {
        guard let audioplayer = self.audioPlayer else {
            return
        }
        
        let currentTime = Int(audioplayer.currentTime)
        
        //store state every 2 seconds, I/O can be expensive
        if currentTime % 2 == 0 {
            UserDefaults.standard.set(currentTime, forKey: self.identifier)
        }
        
        //update current time label
        let timeText = self.formatTime(currentTime)
        self.currentTimeLabel.text = timeText
        
        //calculate book read percentage based on current time
        let percentage = (Float(currentTime) / Float(audioplayer.duration)) * 100
        self.sliderView.value = percentage
        
        let percentageString = String(Int(ceil(percentage)))+"%"
        //only update percentage if there are no chapters
        if self.chapterArray.count == 0 {
            self.percentageLabel.text = percentageString
        }
        
        
        //FIXME: this should only be updated when there's change to current percentage
        UserDefaults.standard.set(percentageString, forKey: self.identifier+"_percentage")
        
        //update chapter
        self.updateCurrentChapter()
        
        //stop timer if the book is finished
        if Int(audioplayer.currentTime) == Int(audioplayer.duration) {
            if self.timer != nil && self.timer.isValid {
                self.timer.invalidate()
            }
            
            self.playButton.setImage(self.playImage, for: UIControlState())
            
            // Once book a book is finished, ask for a review
            UserDefaults.standard.set(true, forKey: "ask_review")
            self.requestReview()
            return
        }
    }
    
    func requestReview(){
        
        // don't do anything if flag isn't true
        guard UserDefaults.standard.bool(forKey: "ask_review"),
            let audioplayer = self.audioPlayer else {
            return
        }
        
        // request for review
        if #available(iOS 10.3, *),
            UIApplication.shared.applicationState == .active,
            Int(audioplayer.currentTime) == Int(audioplayer.duration) {
            SKStoreReviewController.requestReview()
            UserDefaults.standard.set(false, forKey: "ask_review")
        }
    }
    
    func updateCurrentChapter() {
        guard let audioplayer = self.audioPlayer else {
            return
        }
        
        for chapter in self.chapterArray {
            if Int(audioplayer.currentTime) >= chapter.start {
                self.currentChapter = chapter
                self.percentageLabel.text = "Chapter \(chapter.index) of \(self.chapterArray.count)"
                
            }
        }
    }
    
    //leave the slider at max
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            player.currentTime = player.duration
            self.updateTimer()
        }
    }
    
}
