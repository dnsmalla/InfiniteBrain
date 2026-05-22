import Foundation
import InfiniteBrainCore

let url = URL(fileURLWithPath: "/Users/dinsmallade/Desktop/atcoder_book.pdf")
do {
    let result = try InputReader.read(url)
    print("Text length:", result.text.count)
    print("OCR Pages:", result.ocrPages)
    print("Total Pages:", result.totalPages)
    if result.text.count > 100 {
        print("Snippet:", String(result.text.prefix(100)))
    }
} catch {
    print("Error:", error)
}
