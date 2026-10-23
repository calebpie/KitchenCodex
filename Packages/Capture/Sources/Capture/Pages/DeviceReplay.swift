import Foundation

/// A device's Read Fixtures report read again on the Mac (04 §5.1 "Device readings"; ux-notes rows
/// 107, 160, 169): the reader's blocks as the phone saw them, through this build's structurer and
/// readers, so a rule changed here is measured on the phone's blocks before the next device pass,
/// and the phone and the Mac are compared like with like. The report holds what the device read
/// at its build; the replay holds what this build would make of the same blocks.
public enum DeviceReplay {
    /// One photo of the report, read again: the stored scan through `structurer`, the gate's
    /// reading taken from the stored scores with this build's thresholds, the margin lines the
    /// device read standing in for the folio pass, and `outline` for a contents or index page (the
    /// report keeps none; the fixture photo on the Mac gives it). Nil when the photo was unreadable
    /// on the device.
    public static func reading(of photo: DeviceReadingReport.Photo, structurer: PageStructurer = PageStructurer(), gate: PageQualityGate = PageQualityGate(), outline: PageQuad? = nil) -> PageReading? {
        guard let record = photo.scan else { return nil }
        let scan = PageScan(record)
        let quality = photo.quality.map { PageQualityReading(quality: gate.quality(sharpness: $0.sharpness, smudge: $0.smudge), sharpness: $0.sharpness, smudge: $0.smudge) }
        var reading = structurer.read(scan, file: photo.fileName, quality: quality)
        if reading.kind == .recipe || reading.kind == .prose, let margins = photo.marginLines,
           let number = PageStructurer.folioNumber(in: margins), PagePipeline.prefersMarginFolio(reading, margins: number) {
            reading.pageNumbers = [number]
        }
        if let outline = outline ?? photo.outline { reading.outline = outline }
        reading.durations = [.seconds(photo.seconds)]
        return reading
    }
}
