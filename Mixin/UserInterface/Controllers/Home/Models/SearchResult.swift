import Foundation

struct SearchResult {
    
    let target: Target
    let iconUrl: String
    let title: NSAttributedString?
    let badgeImage: UIImage?
    let superscript: String?
    let description: NSAttributedString?
    
    init(user: UserItem, keyword: String) {
        self.target = .contact(user)
        self.iconUrl = user.avatarUrl
        self.title = SearchResult.attributedText(text: user.fullName,
                                                 textAttributes: SearchResult.titleAttributes,
                                                 keyword: keyword,
                                                 keywordAttributes: SearchResult.highlightedTitleAttributes)
        self.badgeImage = SearchResult.userBadgeImage(isVerified: user.isVerified,
                                                      appId: user.appId)
        self.superscript = nil
        if user.identityNumber.contains(keyword) {
            let text = R.string.localizable.search_result_prefix_id() + user.identityNumber
            self.description = SearchResult.attributedText(text: text,
                                                           textAttributes: SearchResult.normalDescriptionAttributes,
                                                           keyword: keyword,
                                                           keywordAttributes: SearchResult.highlightedNormalDescriptionAttributes)
        } else if let phone = user.phone, phone.contains(keyword) {
            let text = R.string.localizable.search_result_prefix_phone() + phone
            self.description = SearchResult.attributedText(text: text,
                                                           textAttributes: SearchResult.normalDescriptionAttributes,
                                                           keyword: keyword,
                                                           keywordAttributes: SearchResult.highlightedNormalDescriptionAttributes)
        } else {
            self.description = nil
        }
    }
    
    init(conversation: ConversationItem, keyword: String) {
        self.target = .conversation(conversation)
        self.iconUrl = conversation.iconUrl
        self.title = SearchResult.attributedText(text: conversation.getConversationName(),
                                                 textAttributes: SearchResult.titleAttributes,
                                                 keyword: keyword,
                                                 keywordAttributes: SearchResult.highlightedTitleAttributes)
        self.badgeImage = nil
        self.superscript = nil
        self.description = nil
    }
    
    init(conversationId: String, category: ConversationCategory, name: String, iconUrl: String, userId: String?, userIsVerified: Bool, userAppId: String?, relatedMessageCount: Int, keyword: String) {
        switch category {
        case .CONTACT:
            self.target = .searchMessageWithContact(conversationId: conversationId,
                                                    userId: userId ?? "",
                                                    userFullName: name)
        case .GROUP:
            self.target = .searchMessageWithGroup(conversationId: conversationId)
        }
        self.iconUrl = iconUrl
        self.title = SearchResult.attributedText(text: name,
                                                 textAttributes: SearchResult.titleAttributes,
                                                 keyword: keyword,
                                                 keywordAttributes: SearchResult.highlightedTitleAttributes)
        self.badgeImage = SearchResult.userBadgeImage(isVerified: userIsVerified, appId: userAppId)
        self.superscript = nil
        let desc = "\(relatedMessageCount)" + R.string.localizable.search_related_messages_count()
        self.description = NSAttributedString(string: desc, attributes: SearchResult.normalDescriptionAttributes)
    }
    
    init(conversationId: String, messageId: String, category: String, content: String, createdAt: String, userId: String, fullname: String, avatarUrl: String, isVerified: Bool, appId: String?, keyword: String) {
        let isData = category.hasSuffix("_DATA")
        self.target = .message(conversationId: conversationId, messageId: messageId, isData: isData, userId: userId, userFullName: fullname, createdAt: createdAt)
        self.iconUrl = avatarUrl
        self.title = SearchResult.attributedText(text: fullname,
                                                 textAttributes: SearchResult.titleAttributes,
                                                 keyword: keyword,
                                                 keywordAttributes: SearchResult.highlightedTitleAttributes)
        self.badgeImage = SearchResult.userBadgeImage(isVerified: isVerified,
                                                      appId: appId)
        self.superscript = createdAt.toUTCDate().timeAgo()
        if isData {
            self.description = NSAttributedString(string: R.string.localizable.notification_content_file(),
                                                  attributes: SearchResult.normalDescriptionAttributes)
        } else {
            // TODO: Tokenize
            self.description = SearchResult.attributedText(text: content,
                                                           textAttributes: SearchResult.largerDescriptionAttributes,
                                                           keyword: keyword,
                                                           keywordAttributes: SearchResult.highlightedLargerDescriptionAttributes)
        }
    }
    
}

extension SearchResult {
    
    enum Target {
        case contact(UserItem)
        case conversation(ConversationItem)
        case searchMessageWithContact(conversationId: String, userId: String, userFullName: String)
        case searchMessageWithGroup(conversationId: String)
        case message(conversationId: String, messageId: String, isData: Bool, userId: String, userFullName: String, createdAt: String)
    }
    
    enum Style {
        case normal
        case largerDescription
    }
    
    private typealias Attributes = [NSAttributedString.Key: Any]
    
    private static let titleFont = UIFont.systemFont(ofSize: 16)
    private static let titleAttributes: Attributes = [
        .font: titleFont,
        .foregroundColor: UIColor.darkText
    ]
    private static let highlightedTitleAttributes: Attributes = [
        .font: titleFont,
        .foregroundColor: UIColor.highlightedText
    ]
    
    private static let normalDescriptionFont = UIFont.systemFont(ofSize: 12)
    private static let normalDescriptionAttributes: Attributes = [
        .font: normalDescriptionFont,
        .foregroundColor: UIColor.descriptionText
    ]
    private static let highlightedNormalDescriptionAttributes: Attributes = [
        .font: normalDescriptionFont,
        .foregroundColor: UIColor.highlightedText
    ]
    
    private static let largerDescriptionFont = UIFont.systemFont(ofSize: 14)
    private static let largerDescriptionAttributes: Attributes = [
        .font: largerDescriptionFont,
        .foregroundColor: UIColor.descriptionText
    ]
    private static let highlightedLargerDescriptionAttributes: Attributes = [
        .font: largerDescriptionFont,
        .foregroundColor: UIColor.highlightedText
    ]
    
    private static func attributedText(text: String, textAttributes: Attributes, keyword: String, keywordAttributes: Attributes) -> NSAttributedString {
        let str = NSMutableAttributedString(string: text, attributes: textAttributes)
        let nsText = NSString(string: text)
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let invalidRange = NSRange(location: NSNotFound, length: 0)
        var enclosingRange = NSRange(location: 0, length: nsText.length)
        while !NSEqualRanges(enclosingRange, invalidRange) {
            let range = nsText.range(of: keyword, options: options, range: enclosingRange)
            guard !NSEqualRanges(range, invalidRange) else {
                break
            }
            str.setAttributes(keywordAttributes, range: range)
            let nextLocation = NSMaxRange(range)
            enclosingRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return str
    }
    
    private static func userBadgeImage(isVerified: Bool, appId: String?) -> UIImage? {
        if isVerified {
            return R.image.ic_user_verified()
        } else if !appId.isNilOrEmpty {
            return R.image.ic_user_bot()
        } else {
            return nil
        }
    }
    
}
