import Foundation

@MainActor
package protocol NoticePresenting: AnyObject {
    func show(_ notice: Notice)
}
