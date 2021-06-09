/**
 * Copyright (c) 2017 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import AVFoundation
import Photos
import Vision
import UIKit


extension CVPixelBuffer {
    
    enum CVPixelBufferCopyError: Error {
        case cannotAllocateBuffer
    }
    
    
    private func documentDirectory() -> String {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                                    .userDomainMask,
                                                                    true)
        return documentDirectory[0]
    }
    
    private func append(toPath path: String,
                        withPathComponent pathComponent: String) -> String? {
        if var pathURL = URL(string: path) {
            pathURL.appendPathComponent(pathComponent)
            
            return pathURL.absoluteString
        }
        
        return nil
    }
    
    private func read(fromDocumentsWithFileName fileName: String) {
        guard let filePath = self.append(toPath: self.documentDirectory(),
                                         withPathComponent: fileName) else {
                                            return
        }
        
        do {
            try String(contentsOfFile: filePath)
        } catch {
            print("Error reading saved file")
        }
    }
    
    private func save(text: String,
                      toDirectory directory: String,
                      withFileName fileName: String) {
        guard let filePath = self.append(toPath: directory,
                                         withPathComponent: fileName) else {
            return
        }
        
        do {
            try text.write(toFile: filePath,
                           atomically: true,
                           encoding: .utf8)
        } catch {
            print("Error", error)
            return
        }
        
        print("Save successful")
    }
    
    func saveRawToFile(){
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0));
        let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(self), to: UnsafeMutablePointer<float16_t>.self)
        let timestamp = NSDate().timeIntervalSince1970
        let fileName = String(timestamp) + ".txt"
        var depths = ""
        for y in 0 ..< height {
          for x in 0 ..< width {
            let pixel = floatBuffer[y * width + x]
            depths += String(describing: pixel) + ", "
          }
            depths += "\n"
        }
//        print(self.documentDirectory())
        self.save(text: depths,
                  toDirectory: self.documentDirectory(),
                  withFileName: fileName)
//        self.read(fromDocumentsWithFileName: fileName)
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
    }
    
    func printDebugInfo() {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        let totalBytes = CVPixelBufferGetDataSize(self)

        print("Depth Map Info: \(width)x\(height)")
        print(" Bytes per Row: \(bytesPerRow)")
        print("   Total Bytes: \(totalBytes)")
    }
    
//    func detectFace(){
//        let image = CIImage(cvPixelBuffer:self)
//        let faceDetection = VNDetectFaceRectanglesRequest()
//        let faceLandmarks = VNDetectFaceLandmarksRequest()
//        let faceLandmarksDetectionRequest = VNSequenceRequestHandler()
//        let faceDetectionRequest = VNSequenceRequestHandler()
//            try? faceDetectionRequest.perform([faceDetection], on: image)
//            if let results = faceDetection.results as? [VNFaceObservation] {
//                if !results.isEmpty {
//                    faceLandmarks.inputFaceObservations = results
//                    try? faceLandmarksDetectionRequest.perform([faceLandmarks], on: image)
//                    if let landmarksResults = faceLandmarks.results as? [VNFaceObservation] {
//                        for observation in landmarksResults {
//                            if(faceLandmarks.inputFaceObservations?.first?.boundingBox) != nil {
//                                if let allPoints = observation.landmarks?.allPoints{
//                                    let width = CVPixelBufferGetWidth(self)
//                                    let height = CVPixelBufferG1vv   etHeight(self)
//                                    let map = allPoints.pointsInImage(imageSize: CGSize(width: width, height: height))
//                                    print(map.count)
//                                    let timestamp = NSDate().timeIntervalSince1970
//                                    let fileName = String(timestamp) + "_landmarks.txt"
//                                    var points = ""
//                                    for point:CGPoint in map{
//                                        let x = Int(point.x)
//                                        let y = Int(point.y)
//                                        points += String(describing: x) + ", " + String(describing: y) + "\n"
//                                    }
//                                    self.save(text: points,
//                                              toDirectory: self.documentDirectory(),
//                                              withFileName: fileName)
////                                    self.read(fromDocumentsWithFileName: fileName)
//                                    
//                                }
//                            }
//                        }
//                    }
//
//                }
//            }
//        }
}
