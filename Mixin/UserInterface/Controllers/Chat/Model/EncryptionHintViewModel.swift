import UIKit

class EncryptionHintViewModel: SystemMessageViewModel {

    override init(message: MessageItem, style: Style, fits layoutWidth: CGFloat) {
        super.init(message: message, style: style, fits: layoutWidth)
        backgroundImage = #imageLiteral(resourceName: "ic_chat_bubble_encryption")
    }
    
}
