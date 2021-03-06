//
//  ReportsViewController.swift
//  check-in
//
//  Created by Joel on 8/8/16.
//  Copyright © 2016 JediMaster. All rights reserved.
//

import Foundation
import UIKit
import MessageUI
import PDFGenerator
import CoreData

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


class ReportsViewController: UIViewController, MFMailComposeViewControllerDelegate{
    // declare MIME (Multipurpose Internet Mail Extension)
    // it defines what kind of information to send via email
    fileprivate enum MIMEType: String {
        case pdf = "application/pdf"
        case png = "image/png"
        
        init? (type: String) {
            switch type.lowercased() {
            case "png": self = .png
            case "pdf": self = .pdf
            default: return nil
            }
        }
    }
    
    @IBOutlet var emailTextField: UITextField!
    @IBOutlet var sendPDFButton: UIButton!
    @IBOutlet var tableview: UITableView!
    
    var titleLabel: UILabel!
    let cellIdentifier = "reportsCell"
    var appDelegate = UIApplication.shared.delegate as! AppDelegate
    var checkinEvents = [CheckInEvent]()
    
    //------------------------------------------------------------------------------
    // MARK: Lifecycle Methods
    //------------------------------------------------------------------------------
    override func viewDidLoad() {
        self.titleLabel = UILabel(frame: CGRect(x: 280, y: 100, width: 700, height: 50))
        let df = DateFormatter()
        df.dateFormat = "MM-dd-yyyy"
        let dateString = df.string(from: Date.getCurrentLocalDate())
        let title = "Reporte del dia".localized()
        self.titleLabel.text = "\(title) (\(dateString))"
        self.view.addSubview(self.titleLabel)
        self.titleLabel.isHidden = true
        
        let dataController = DataController.sharedInstance
        dataController.getCheckinRecords()
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: Notification.didReceiveCheckinRecordsNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(setText), name: Notification.languageChangeNotification, object: nil)

    }
    
    override func viewWillAppear(_ animated: Bool) {
        setText()
    }
    
    override func didRotate(from fromInterfaceOrientation: UIInterfaceOrientation) {
        if UIDevice.current.orientation == .portraitUpsideDown {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let vc = storyboard.instantiateViewController(withIdentifier: "checkInViewController") as! CheckInViewController
            vc.tabBarControllerRef = self.tabBarController
            vc.tabSelected = 1
            self.present(vc, animated: true, completion: nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    
    //------------------------------------------------------------------------------
    // MARK: Tableview Methods
    //------------------------------------------------------------------------------
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let reportsHeaderView = tableview.dequeueReusableCell(withIdentifier: "reportsHeaderView") as! ReportsHeaderView
        reportsHeaderView.nameLabel.text = "Name".localized()
        reportsHeaderView.checkinTimeLabel.text = "Checked-in".localized()
        reportsHeaderView.serviceLabel.text = "Service".localized()
        reportsHeaderView.stylistLabel.text = "Stylist".localized()
        reportsHeaderView.paymentTypeLabel.text = "Payment".localized()
        reportsHeaderView.amountLabel.text = "Amount".localized()
        return reportsHeaderView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 40
    }
    
    func numberOfSectionsInTableView(_ tableView: UITableView!) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView!, numberOfRowsInSection section: Int) -> Int {
        return self.checkinEvents.count
    }
    
    func tableView(_ tableView: UITableView!, cellForRowAtIndexPath indexPath: IndexPath!) -> UITableViewCell! {
        let cell = tableView.dequeueReusableCell(withIdentifier: self.cellIdentifier)! as! ReportsCustomCell
        let checkinEvent = self.checkinEvents[indexPath.row]
        cell.countLabel.text = String(indexPath.row + 1)
        cell.clientNameLabel.text = checkinEvent.name
        let df = DateFormatter()
        df.dateFormat = "MM/dd/yy h:mm a"
        let dateString = df.string(from: checkinEvent.checkinTimestamp! as Date)
        cell.checkintTimeLabel.text = dateString
        cell.serviceTypeLabel.text = checkinEvent.service == "" || checkinEvent.service == nil ? "no value".localized() : checkinEvent.service
        cell.stylistLabel.text = checkinEvent.stylist == "" || checkinEvent.stylist == nil ? "no value".localized() : checkinEvent.stylist
        cell.amountChargedLabel.text = checkinEvent.amountCharged == "" || checkinEvent.amountCharged == nil ? "no value".localized() : "$\(checkinEvent.amountCharged!)"
        cell.paymentTypeLabel.text = checkinEvent.paymentType == "" || checkinEvent.paymentType == nil ? "no value".localized() : checkinEvent.paymentType
        
        

        return cell
    }
    
    //------------------------------------------------------------------------------
    // MARK: Action Methods
    //------------------------------------------------------------------------------
    @IBAction func sendEmailWithAttachment(_ sender: AnyObject) {
        if self.emailTextField.text?.characters.count > 0 {
            let identifier = String(describing: Date.getCurrentLocalDate())
            generatePDF(identifier)
        }
        else {
            alert("Email".localized(), message: "Email address is missing".localized())
        }
    }
    
    //------------------------------------------------------------------------------
    // MARK: Private Methods
    //------------------------------------------------------------------------------
    @objc fileprivate func setText() {
        self.sendPDFButton.setTitle("Send PDF".localized(), for: .normal)
        self.emailTextField.placeholder = "email".localized()
        self.tableview.reloadData()
    }
    
    @objc fileprivate func update(_ notification: Notification) {
        DispatchQueue.main.async {
            var fetch: NSFetchRequest<NSFetchRequestResult>?
            if #available(iOS 10.0, *) {
                fetch = CheckInEvent.fetchRequest()
            } else {
                // Fallback on earlier versions
                fetch = NSFetchRequest(entityName: Constants.checkInEvent)
            }
            fetch?.predicate = self.createPredicate()
            do {
                self.checkinEvents = try self.appDelegate.managedObjectContext.fetch(fetch!) as! [CheckInEvent]
            }
            catch {
                print("Class:\(#file)\n Line:\(#line)\n Error:\(error)")
            }
            
            self.tableview.reloadData()
        }
    }
    
    fileprivate func createPredicate() -> NSPredicate {
        var predicates: [NSPredicate]! = []
        let calendar = Calendar.current
        var components: DateComponents = (calendar as NSCalendar).components([.day, .month, .year], from: Date())
        let today = calendar.date(from: components)!
        components.day = components.day!+1
        let tomorrow = calendar.date(from: components)!
        
        let subPredicateFrom = NSPredicate(format: "checkinTimestamp >= %@", today as CVarArg)
        predicates.append(subPredicateFrom)
        
        let subPredicateTo = NSPredicate(format: "checkinTimestamp < %@", tomorrow as CVarArg)
        predicates.append(subPredicateTo)
        
        let subPredicateCompleted = NSPredicate(format: "status == 'completed'")
        predicates.append(subPredicateCompleted)
        
        return NSCompoundPredicate(type: .and, subpredicates: predicates)
    }
    
    fileprivate func createPdfFromView(_ aView: UIView, saveToDocumentsWithIdentifier fileName: String)
    {
        self.emailTextField.isHidden = true
        self.sendPDFButton.isHidden = true
        self.titleLabel.isHidden = false
        
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, aView.bounds, nil)
        UIGraphicsBeginPDFPage()
        
        guard let pdfContext = UIGraphicsGetCurrentContext() else { return }
        
        aView.layer.render(in: pdfContext)
        UIGraphicsEndPDFContext()
        self.emailTextField.isHidden = false
        self.sendPDFButton.isHidden = false
        self.titleLabel.isHidden = true
        
        if let documentDirectories = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let filePath = documentDirectories + "/" + fileName
            pdfData.write(toFile: filePath, atomically: true)
            showMailComposerWith(filePath, fileName: fileName)
        }
    }
    
    fileprivate func alert(_ title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
    
    fileprivate func showMailComposerWith(_ filePath: String, fileName: String) {
        if MFMailComposeViewController.canSendMail() {
            let subject = "Report".localized()
            let messageBody = "End of day report".localized()
            let toRecipient = self.emailTextField.text
            let mailComposer = MFMailComposeViewController()
            mailComposer.mailComposeDelegate = self
            mailComposer.setSubject(subject)
            mailComposer.setMessageBody(messageBody, isHTML: true)
            mailComposer.setToRecipients([toRecipient!])

            if let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                mailComposer.addAttachmentData(fileData, mimeType: "application/pdf", fileName: fileName)
                present(mailComposer, animated: true, completion: nil)
            }
        }
        else {
            alert("Email".localized(), message: "This iPad has not been setup with an email account".localized())
        }
    }
    
    func generatePDF(_ fileName: String) {
        let v1 = self.tableview
        let identifier = String(describing: Date.getCurrentLocalDate())
        let homeDir = NSHomeDirectory() as NSString
        let path = homeDir.appending("/\(fileName)")
        do {
            try PDFGenerator.generate(v1!, to: path)

        }
        catch {
            
        }

        showMailComposerWith(path, fileName: identifier)
    }
    
    //------------------------------------------------------------------------------
    // MARK: MFMailComposeViewControllerDelegate Methods
    //------------------------------------------------------------------------------
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true, completion: nil)

        switch result.rawValue {
        case MFMailComposeResult.failed.rawValue:
            alert("failed", message: (error?.localizedDescription)!)
        default: return
        }
    }
}
