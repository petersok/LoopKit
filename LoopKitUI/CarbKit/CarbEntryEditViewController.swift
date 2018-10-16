//
//  CarbEntryEditViewController.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit


public final class CarbEntryEditViewController: UITableViewController {
    
    var navigationDelegate = CarbEntryNavigationDelegate()
    
    public var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes? {
        didSet {
            if let times = defaultAbsorptionTimes {
                orderedAbsorptionTimes = [times.fast, times.medium, times.slow]
            }
        }
    }

    fileprivate var orderedAbsorptionTimes = [TimeInterval]()

    public var preferredUnit = HKUnit.gram()

    public var maxQuantity = HKQuantity(unit: .gram(), doubleValue: 250)

    /// Entry configuration values. Must be set before presenting.
    public var absorptionTimePickerInterval = TimeInterval(minutes: 30)

    public var maxAbsorptionTime = TimeInterval(hours: 16)

    public var maximumDateFutureInterval = TimeInterval(hours: 4)

    public var originalCarbEntry: StoredCarbEntry? {
        didSet {
            if let entry = originalCarbEntry {
                quantity = entry.quantity
                date = entry.startDate
                foodType = entry.foodType
                absorptionTime = entry.absorptionTime

                absorptionTimeWasEdited = true
                usesCustomFoodType = true
            }
        }
    }

    fileprivate var quantity: HKQuantity?
    
    fileprivate var unusedQuantity: HKQuantity?
    
    fileprivate var carbQuantity: Int? = 0
    
    fileprivate var fatQuantity: Int? = 0
    
    fileprivate var proteinQuantity: Int? = 0
    
    fileprivate var FPUQuantity: HKQuantity?

    fileprivate var date = Date()

    fileprivate var foodType: String?

    fileprivate var absorptionTime: TimeInterval?

    fileprivate var absorptionTimeWasEdited = false

    fileprivate var usesCustomFoodType = false

    public var updatedCarbEntry: NewCarbEntry? {
        if  let quantity = quantity,
            let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium
        {
            if let o = originalCarbEntry, o.quantity == quantity && o.startDate == date && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }
            
            return NewCarbEntry(
                quantity: quantity,
                startDate: date,
                foodType: foodType,
                absorptionTime: absorptionTime,
                externalID: originalCarbEntry?.externalID
            )
        } else {
            return nil
        }
    }
    
    public var updatedFPUCarbEntry: NewCarbEntry? {
        if  let quantity = quantity,
            let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium
        {
            if let o = originalCarbEntry, o.quantity == quantity && o.startDate == date && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }
            
            let FPCaloriesRatio = 120 // This should be a user-setable option.
            let onsetDelay: Double = 60 // Minutes to delay FPU dose. Should be user-setable option.
            let proteinCalories = proteinQuantity! * 4
            let fatCalories = fatQuantity! * 9
            var lowCarbMultiplier: Double = Double(carbQuantity!) 
            
            // If carbs are 30 or more, then fat and protein are full weught.
            // If carbs are 0, then fat and protein are 50% weight.
            // If carbs are 15, then fat and protein are 75% weight.
            
            if carbQuantity! >= 30 {
                lowCarbMultiplier = 1.0
            } else {
                lowCarbMultiplier = (lowCarbMultiplier / 60.0) + 0.5
            }
            
            let FPU = Double(proteinCalories + fatCalories) / Double(FPCaloriesRatio)
            
            let carbEquivilant = FPU * 10 * lowCarbMultiplier
            
            var squareWaveDuration = Double(2) + FPU
            
            if squareWaveDuration > 16 { // Set some reasonable max.
                squareWaveDuration = 16
            }
            
            if carbEquivilant >= 1 {
                
                return NewCarbEntry(
                    quantity: HKQuantity(unit: .gram(), doubleValue: carbEquivilant),
                    startDate: date + 60 * onsetDelay,
                    foodType: foodType,
                    absorptionTime: .hours(squareWaveDuration),
                    externalID: originalCarbEntry?.externalID)
                
            } else {
                
                return nil
            }
            
        } else {
            return nil
        }
    }

    private var isSampleEditable: Bool {
        return originalCarbEntry?.createdByCurrentApp != false
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 44
        tableView.register(DateAndDurationTableViewCell.nib(), forCellReuseIdentifier: DateAndDurationTableViewCell.className)

        if originalCarbEntry != nil {
            title = LocalizedString("carb-entry-title-edit", value: "Edit Carb Entry", comment: "The title of the view controller to edit an existing carb entry")
        } else {
            title = LocalizedString("carb-entry-title-add", value: "Add Carb Entry", comment: "The title of the view controller to create a new carb entry")
        }
    }

    private var foodKeyboard: CarbAbsorptionInputController!

    @IBOutlet weak var saveButtonItem: UIBarButtonItem!

    // MARK: - Table view data source

    fileprivate enum Row: Int {
        case value
        case fat        // RSS
        case protein    // RSS
        case date
        case foodType
        case absorptionTime

        static let count = 6
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Row(rawValue: indexPath.row)! {
        case .value:
            let cell = tableView.dequeueReusableCell(withIdentifier: CarbDecimalTextFieldTableViewCell.className) as! CarbDecimalTextFieldTableViewCell

            if let quantity = quantity {
                cell.number = NSNumber(value: quantity.doubleValue(for: preferredUnit))
            }
            cell.textField.isEnabled = isSampleEditable
            cell.unitLabel?.text = String(describing: preferredUnit)

            if originalCarbEntry == nil {
                cell.textField.becomeFirstResponder()
            }

            cell.delegate = self

            return cell
        case .fat:
            let cell = tableView.dequeueReusableCell(withIdentifier: FatDecimalTextFieldTableViewCell.className) as! FatDecimalTextFieldTableViewCell
            
            if let quantity = quantity {
                //cell.number = NSNumber(value: quantity.doubleValue(for: preferredUnit))
                cell.number = NSNumber(value: 0.0)
            }
            cell.textField.isEnabled = isSampleEditable
            cell.unitLabel?.text = String(describing: preferredUnit)
            
            if originalCarbEntry == nil {
                cell.textField.becomeFirstResponder()
            }
            
            cell.delegate = self
            
            return cell
        case .protein:
            let cell = tableView.dequeueReusableCell(withIdentifier: ProteinDecimalTextFieldTableViewCell.className) as! ProteinDecimalTextFieldTableViewCell
            
            if let quantity = quantity {
                //cell.number = NSNumber(value: quantity.doubleValue(for: preferredUnit))
                cell.number = NSNumber(value: 0.0)
            }
            cell.textField.isEnabled = isSampleEditable
            cell.unitLabel?.text = String(describing: preferredUnit)
            
            if originalCarbEntry == nil {
                cell.textField.becomeFirstResponder()
            }
            
            cell.delegate = self
            
            return cell
 
        case .date:
            let cell = tableView.dequeueReusableCell(withIdentifier: DateAndDurationTableViewCell.className) as! DateAndDurationTableViewCell

            cell.titleLabel.text = LocalizedString("Date", comment: "Title of the carb entry date picker cell")
            cell.datePicker.isEnabled = isSampleEditable
            cell.datePicker.datePickerMode = .dateAndTime
            cell.datePicker.maximumDate = Date() + maximumDateFutureInterval
            cell.datePicker.minuteInterval = 1
            cell.date = date
            cell.delegate = self

            return cell
        case .foodType:
            if usesCustomFoodType {
                let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldTableViewCell.className, for: indexPath) as! TextFieldTableViewCell

                cell.textField.text = foodType
                cell.delegate = self

                if let textField = cell.textField as? CustomInputTextField {
                    if foodKeyboard == nil {
                        foodKeyboard = storyboard?.instantiateViewController(withIdentifier: CarbAbsorptionInputController.className) as? CarbAbsorptionInputController
                        foodKeyboard.delegate = self
                    }

                    textField.customInput = foodKeyboard
                }

                if originalCarbEntry == nil {
                    cell.textField.becomeFirstResponder()
                }

                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: FoodTypeShortcutCell.className, for: indexPath) as! FoodTypeShortcutCell

                if absorptionTime == nil {
                    cell.selectionState = .medium
                }

                cell.delegate = self

                return cell
            }
        case .absorptionTime:
            let cell = tableView.dequeueReusableCell(withIdentifier: DateAndDurationTableViewCell.className) as! DateAndDurationTableViewCell

            cell.titleLabel.text = LocalizedString("Absorption Time", comment: "Title of the carb entry absorption time cell")
            cell.datePicker.isEnabled = isSampleEditable
            cell.datePicker.datePickerMode = .countDownTimer
            cell.datePicker.minuteInterval = Int(absorptionTimePickerInterval.minutes)

            if let duration = absorptionTime ?? defaultAbsorptionTimes?.medium {
                cell.duration = duration
            }

            cell.maximumDuration = maxAbsorptionTime
            cell.delegate = self

            return cell
        }
    }

    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return LocalizedString("Choose a longer absorption time for larger meals, or those containing fats and proteins. This is only guidance to the algorithm and need not be exact.", comment: "Carb entry section footer text explaining absorption time")
    }

    // MARK: - UITableViewDelegate

    public override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        tableView.endEditing(false)
        tableView.beginUpdates()
        hideDatePickerCells(excluding: indexPath)
        return indexPath
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch tableView.cellForRow(at: indexPath) {
        case is FoodTypeShortcutCell:
            usesCustomFoodType = true
            tableView.reloadRows(at: [IndexPath(row: Row.foodType.rawValue, section: 0)], with: .none)
        default:
            break
        }

        tableView.endUpdates()
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Navigation

    public override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        self.tableView.endEditing(true)

        guard let button = sender as? UIBarButtonItem, button == saveButtonItem else {
            quantity = nil
            return super.shouldPerformSegue(withIdentifier: identifier, sender: sender)
        }

        guard let absorptionTime = absorptionTime ?? defaultAbsorptionTimes?.medium else {
            return false
        }
        guard absorptionTime <= maxAbsorptionTime else {
            navigationDelegate.showAbsorptionTimeValidationWarning(for: self, maxAbsorptionTime: maxAbsorptionTime)
            return false
        }

        guard let quantity = quantity, quantity.doubleValue(for: HKUnit.gram()) > 0 else { return false }
        guard quantity.compare(maxQuantity) != .orderedDescending else {
            navigationDelegate.showMaxQuantityValidationWarning(for: self, maxQuantityGrams: maxQuantity.doubleValue(for: .gram()))
            return false
        }

        return true
    }
}


extension CarbEntryEditViewController: TextFieldTableViewCellDelegate {
    public func textFieldTableViewCellDidBeginEditing(_ cell: TextFieldTableViewCell) {
        // Collapse any date picker cells to save space
        tableView.beginUpdates()
        hideDatePickerCells()
        tableView.endUpdates()
    }

    public func textFieldTableViewCellDidEndEditing(_ cell: TextFieldTableViewCell) {
        guard let row = tableView.indexPath(for: cell)?.row else { return }

        switch Row(rawValue: row) {
        case .value?:
            if let cell = cell as? CarbDecimalTextFieldTableViewCell, let number = cell.number {
                carbQuantity = Int(number.doubleValue)
                quantity = HKQuantity(unit: preferredUnit, doubleValue: number.doubleValue)
            } else {
                quantity = nil
            }
        case .fat?:
            if let cell = cell as? FatDecimalTextFieldTableViewCell, let number = cell.number {
                fatQuantity = Int(number.doubleValue)
            } else {
                fatQuantity = 0 // Make 0, not nil if no value to prevent crash later.
            }
        case .protein?:
            if let cell = cell as? ProteinDecimalTextFieldTableViewCell, let number = cell.number {
                proteinQuantity = Int(number.doubleValue)
            } else {
                proteinQuantity = 0 // Make 0, not nil if no value to prevent crash later.
            }
        case .foodType?:
            foodType = cell.textField.text
        default:
            break
        }
    }
}


extension CarbEntryEditViewController: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {
        guard let row = tableView.indexPath(for: cell)?.row else { return }

        switch Row(rawValue: row) {
        case .date?:
            date = cell.date
        case .absorptionTime?:
            absorptionTime = cell.duration
            absorptionTimeWasEdited = true
        default:
            break
        }
    }
}


extension CarbEntryEditViewController: FoodTypeShortcutCellDelegate {
    func foodTypeShortcutCellDidUpdateSelection(_ cell: FoodTypeShortcutCell) {
        var absorptionTime: TimeInterval?

        switch cell.selectionState {
        case .fast:
            absorptionTime = defaultAbsorptionTimes?.fast
        case .medium:
            absorptionTime = defaultAbsorptionTimes?.medium
        case .slow:
            absorptionTime = defaultAbsorptionTimes?.slow
        case .custom:
            tableView.beginUpdates()
            usesCustomFoodType = true
            tableView.reloadRows(at: [IndexPath(row: Row.foodType.rawValue, section: 0)], with: .fade)
            tableView.endUpdates()
        }

        if let absorptionTime = absorptionTime {
            self.absorptionTime = absorptionTime

            if let cell = tableView.cellForRow(at: IndexPath(row: Row.absorptionTime.rawValue, section: 0)) as? DateAndDurationTableViewCell {
                cell.duration = absorptionTime
            }
        }
    }
}


extension CarbEntryEditViewController: CarbAbsorptionInputControllerDelegate {
    func carbAbsorptionInputControllerDidAdvanceToStandardInputMode(_ controller: CarbAbsorptionInputController) {
        if let cell = tableView.cellForRow(at: IndexPath(row: Row.foodType.rawValue, section: 0)) as? TextFieldTableViewCell, let textField = cell.textField as? CustomInputTextField, textField.customInput != nil {
            let customInput = textField.customInput
            textField.customInput = nil
            textField.resignFirstResponder()
            textField.becomeFirstResponder()
            textField.customInput = customInput
        }
    }

    func carbAbsorptionInputControllerDidSelectItemInSection(_ section: Int) {
        guard !absorptionTimeWasEdited, section < orderedAbsorptionTimes.count else {
            return
        }

        let lastAbsorptionTime = self.absorptionTime
        self.absorptionTime = orderedAbsorptionTimes[section]

        if let cell = tableView.cellForRow(at: IndexPath(row: Row.absorptionTime.rawValue, section: 0)) as? DateAndDurationTableViewCell {
            cell.duration = max(lastAbsorptionTime ?? 0, orderedAbsorptionTimes[section])
        }
    }
}
