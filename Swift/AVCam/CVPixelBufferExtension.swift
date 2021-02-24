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

extension CVPixelBuffer {
    
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
            let savedString = try String(contentsOfFile: filePath)
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
        print(self.documentDirectory())
        self.save(text: depths,
                  toDirectory: self.documentDirectory(),
                  withFileName: fileName)
        self.read(fromDocumentsWithFileName: fileName)
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
    }
  
    func normalize(mask:CVPixelBuffer) {
    let width = CVPixelBufferGetWidth(self)
    let height = CVPixelBufferGetHeight(self)
    self.printDebugInfo()
    mask.printDebugInfo()
    CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0));
    let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(self), to: UnsafeMutablePointer<float16_t>.self)
    CVPixelBufferLockBaseAddress(mask, CVPixelBufferLockFlags(rawValue: 0));
    let maskBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(mask), to: UnsafeMutablePointer<UInt8>.self)
    var minPixel: float16_t = 20.0
    var maxPixel: float16_t = 0.0
    for y in 0 ..< height {
      for x in 0 ..< width {
        let pixel = floatBuffer[y * width + x]
        if(isCovered(x:x, y:y, mask:maskBuffer)){
            maxPixel = max(pixel, maxPixel)
            minPixel = min(pixel, minPixel)
        }
      }
    }
    minPixel = 2
    for y in 0 ..< height {
      for x in 0 ..< width {
        if(isCovered(x:x, y:y, mask:maskBuffer)){
            let pixel = floatBuffer[y * width + x]
            if #available(iOS 14.0, *) {
                let range = maxPixel - minPixel
                floatBuffer[y * width + x] =  (pixel - minPixel)/range
            } else {
                // Fallback on earlier versions
            }
        }else{
            floatBuffer[y * width + x] = 0
        }
      }
    }

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
    
  func isCovered(x:Int, y:Int, mask:UnsafeMutablePointer<UInt8>) -> Bool{
//    Depth Map Info: 640x480 (max y = 480, max x = 640)
//     Bytes per Row: 1280
//       Total Bytes: 614400
//    Depth Map Info: 1158x1544
//     Bytes per Row: 1216
//       Total Bytes: 1877504
    let scale = (10000 * 1544) / 640
    let row = 1216
    let index = ((480 - y) + x * row) * scale
    let int_index = Int(round(Double(index) / 10000))
//    return mask[int_index] > 100
    return true // I have no idea why this does not work :((((
  }
}
