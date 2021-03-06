//
//  ChaptersViewController.swift
//  Audiobook Player
//
//  Created by Gianni Carlo on 7/23/16.
//  Copyright © 2016 Tortuga Power. All rights reserved.
//

import UIKit
import MediaPlayer

struct Chapter {
    var title:String
    var start:Int
    var duration:Int
    var index:Int
}

class ChaptersViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var vfxBackgroundView: UIVisualEffectView!
    
    var chapterArray:[Chapter]!
    var currentChapter:Chapter!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.vfxBackgroundView.effect = UIBlurEffect(style: .light)
        self.tableView.tableFooterView = UIView()
        self.tableView.reloadData()
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    override var preferredStatusBarUpdateAnimation : UIStatusBarAnimation {
        return .slide
    }
    
    
    @IBAction func didPressClose(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}

extension ChaptersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chapterArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChapterViewCell", for: indexPath) as! ChapterViewCell
        let chapter = self.chapterArray[indexPath.row]
        cell.titleLabel.text = chapter.title
        cell.durationLabel.text = formatTime(chapter.start)
        cell.titleLabel.highlightedTextColor = UIColor.black
        cell.durationLabel.highlightedTextColor = UIColor.black
        
        if self.currentChapter.index == chapter.index {
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .top)
        }
        
        return cell
    }
}

extension ChaptersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let chapter = self.chapterArray[indexPath.row]
        self.currentChapter = chapter
        self.performSegue(withIdentifier: "selectedChapterSegue", sender: self)
    }
}

class ChapterViewCell: UITableViewCell {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    
}
