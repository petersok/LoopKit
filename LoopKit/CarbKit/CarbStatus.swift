//
//  CarbStatus.swift
//  LoopKit
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


public struct CarbStatus<T: CarbEntry> {
    /// Details entered by the user
    public let entry: T

    /// The last-computed absorption of the carbs
    public let absorption: AbsorbedCarbValue?

    /// The timeline of observed carb absorption. Nil if observed absorption is less than the modeled minimum
    public let observedTimeline: [CarbValue]?
}


// Masquerade as a carb entry, substituting AbsorbedCarbValue's interpretation of absorption time
extension CarbStatus: SampleValue {
    public var quantity: HKQuantity {
        return entry.quantity
    }

    public var startDate: Date {
        return entry.startDate
    }
}


extension CarbStatus: CarbEntry {
    public var absorptionTime: TimeInterval? {
        return absorption?.estimatedDate.duration ?? entry.absorptionTime
    }
}


extension CarbStatus {
    
    var absorptionModel: CarbAbsorptionComputable {
      return CarbAbsorptionModel.settings.absorptionModel
    }
    
    func dynamicCarbsOnBoard(at date: Date, defaultAbsorptionTime: TimeInterval, delay: TimeInterval, delta: TimeInterval) -> Double {
        guard date >= startDate - delta,
            let absorption = absorption
        else {
            // We have to have absorption info for dynamic calculation
            return entry.carbsOnBoard(at: date, defaultAbsorptionTime: defaultAbsorptionTime, delay: delay)
        }

        let unit = HKUnit.gram()

        guard let observedTimeline = observedTimeline, let observationEnd = observedTimeline.last?.endDate else {
            // Less than minimum observed or observation not yet started; calc based on modeled absorption rate
            let total = absorption.total.doubleValue(for: unit)
            let time = date.timeIntervalSince(startDate) - delay
            let absorptionTime = absorption.estimatedDate.duration
            return absorptionModel.unabsorbedCarbs(of: total, atTime: time, absorptionTime: absorptionTime)
        }

        guard date <= observationEnd else {
            // Predicted absorption for remaining carbs, post-observation
            let time = date.timeIntervalSince(startDate) - delay
            let timeAtObservationEnd = observationEnd.timeIntervalSince(startDate) - delay
            let total = absorption.total.doubleValue(for: unit)
            let remaining = absorption.remaining.doubleValue(for: unit)
            let dynamicAbsorptionTime = timeAtObservationEnd + absorption.estimatedTimeRemaining
            let unabsorbedAtTime = absorptionModel.unabsorbedCarbs(of: total, atTime: time, absorptionTime: dynamicAbsorptionTime)
            let unabsorbedAtObservationEnd = absorptionModel.unabsorbedCarbs(of: total, atTime: timeAtObservationEnd, absorptionTime: dynamicAbsorptionTime)
            let unabsorbedCarbs = max(remaining + unabsorbedAtTime - unabsorbedAtObservationEnd, 0.0)
            return unabsorbedCarbs
        }

        // Observed absorption
        // TODO: This creates an O(n^2) situation for COB timelines
        let total = entry.quantity.doubleValue(for: unit)
        return max(observedTimeline.filter({ $0.endDate <= date }).reduce(total) { (total, value) -> Double in
            return total - value.quantity.doubleValue(for: unit)
        }, 0)
    }

    func dynamicAbsorbedCarbs(at date: Date, absorptionTime: TimeInterval, delay: TimeInterval, delta: TimeInterval) -> Double {
        guard date >= startDate,
            let absorption = absorption
        else {
            // We have to have absorption info for dynamic calculation
            return entry.absorbedCarbs(at: date, absorptionTime: absorptionTime, delay: delay)
        }

        let unit = HKUnit.gram()

        guard let observedTimeline = observedTimeline, let observationEnd = observedTimeline.last?.endDate else {
            // Less than minimum observed or observation not yet started; calc based on modeled absorption rate
            let total = absorption.total.doubleValue(for: unit)
            let time = date.timeIntervalSince(startDate) - delay
            let absorptionTime = absorption.estimatedDate.duration
            return absorptionModel.absorbedCarbs(of: total, atTime: time, absorptionTime: absorptionTime)
        }

        guard date <= observationEnd else {
            // Predicted absorption for remaining carbs, post-observation
            let time = date.timeIntervalSince(startDate) - delay
            let timeAtObservationEnd = observationEnd.timeIntervalSince(startDate) - delay
            let total = absorption.total.doubleValue(for: unit)
            let observed = absorption.observed.doubleValue(for: unit)
            let dynamicAbsorptionTime = timeAtObservationEnd + absorption.estimatedTimeRemaining
            let absorbedAtTime = absorptionModel.absorbedCarbs(of: total, atTime: time, absorptionTime: dynamicAbsorptionTime)
            let absorbedAtObservationEnd = absorptionModel.absorbedCarbs(of: total, atTime: timeAtObservationEnd, absorptionTime: dynamicAbsorptionTime)
            let absorbedCarbs = observed + absorbedAtTime - absorbedAtObservationEnd
            return absorbedCarbs
        }

        // Observed absorption
        // TODO: This creates an O(n^2) situation for carb effect timelines
        var sum: Double = 0
        var beforeDate = observedTimeline.filter { (value) -> Bool in
            value.startDate.addingTimeInterval(delta) <= date
        }

        // Apply only a portion of the value if it extends past the final value
        if let last = beforeDate.popLast() {
            let observationInterval = DateInterval(start: last.startDate, end: last.endDate)
            if  observationInterval.duration > 0,
                let calculationInterval = DateInterval(start: last.startDate, end: date).intersection(with: observationInterval)
            {
                sum += calculationInterval.duration / observationInterval.duration * last.quantity.doubleValue(for: unit)
            }
        }

        return min(beforeDate.reduce(sum) { (sum, value) -> Double in
            return sum + value.quantity.doubleValue(for: unit)
        }, quantity.doubleValue(for: unit))
    }
}
