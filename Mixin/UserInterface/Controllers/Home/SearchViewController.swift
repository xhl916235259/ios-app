import UIKit
import PhoneNumberKit
import Alamofire

class SearchViewController: UIViewController, SearchableViewController {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var recentAppsContainerView: UIView!
    
    let cancelButton = SearchCancelButton()
    
    var wantsNavigationSearchBox: Bool {
        return true
    }
    
    var navigationSearchBoxInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 20, bottom: 0, right: cancelButton.frame.width + cancelButtonRightMargin)
    }
    
    private let resultLimit = 3
    private let idOrPhoneCharacterSet = Set("+0123456789")
    private let phoneNumberKit = PhoneNumberKit()
    
    private var queue = OperationQueue()
    private var assets = [AssetSearchResult]()
    private var users = [SearchResult]()
    private var conversationsByName = [SearchResult]()
    private var conversationsByMessage = [SearchResult]()
    private var lastKeyword: Keyword?
    private var recentAppsViewController: RecentAppsViewController?
    private var searchNumberRequest: Request?
    
    private lazy var userWindow = UserWindow.instance()
    
    private var keywordMaybeIdOrPhone: Bool {
        guard let trimmedKeyword = self.keyword?.trimmed else {
            return false
        }
        guard trimmedKeyword.count >= 4 else {
            return false
        }
        guard idOrPhoneCharacterSet.isSuperset(of: trimmedKeyword) else {
            return false
        }
        if trimmedKeyword.contains("+") {
            return (try? phoneNumberKit.parse(trimmedKeyword)) != nil
        } else {
            return true
        }
    }
    
    private var shouldShowSearchNumber: Bool {
        return users.isEmpty && keywordMaybeIdOrPhone
    }
    
    private var searchNumberCell: SearchNumberCell? {
        let indexPath = IndexPath(row: 0, section: Section.searchNumber.rawValue)
        return tableView.cellForRow(at: indexPath) as? SearchNumberCell
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let vc = segue.destination as? RecentAppsViewController {
            recentAppsViewController = vc
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        queue.maxConcurrentOperationCount = 1
        navigationItem.title = " "
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: cancelButton)
        tableView.register(SearchHeaderView.self,
                           forHeaderFooterViewReuseIdentifier: ReuseId.header)
        tableView.register(SearchFooterView.self,
                           forHeaderFooterViewReuseIdentifier: ReuseId.footer)
        tableView.register(R.nib.searchResultCell)
        tableView.register(R.nib.assetCell)
        let tableHeaderView = UIView()
        tableHeaderView.frame = CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude)
        tableView.tableHeaderView = tableHeaderView
        tableView.dataSource = self
        tableView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        searchTextField.addTarget(self, action: #selector(searchAction(_:)), for: .editingChanged)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchTextField.text = lastKeyword?.raw
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchTextField.removeTarget(self, action: #selector(searchAction(_:)), for: .editingChanged)
    }
    
    @IBAction func searchAction(_ sender: Any) {
        guard let keyword = self.keyword else {
            showRecentApps()
            lastKeyword = nil
            return
        }
        guard keyword != lastKeyword else {
            return
        }
        searchNumberRequest?.cancel()
        searchNumberRequest = nil
        showSearchResults()
        let limit = self.resultLimit + 1 // Query 1 more object to see if there's more objects than the limit
        let op = BlockOperation()
        op.addExecutionBlock { [unowned op, weak self] in
            guard self != nil, !op.isCancelled else {
                return
            }
            let trimmedKeyword = keyword.trimmed
            let assets = AssetDAO.shared.getAssets(keyword: trimmedKeyword, limit: limit)
                .map { AssetSearchResult(asset: $0, keyword: trimmedKeyword) }
            let contacts = UserDAO.shared.getUsers(keyword: trimmedKeyword, limit: limit)
                .map { SearchResult(user: $0, keyword: trimmedKeyword) }
            let conversationsByName = ConversationDAO.shared.getGroupOrStrangerConversation(withNameLike: trimmedKeyword, limit: limit)
                .map { SearchResult(conversation: $0, keyword: trimmedKeyword) }
            let conversationsByMessage = ConversationDAO.shared.getConversation(withMessageLike: trimmedKeyword, limit: limit)
            DispatchQueue.main.sync {
                guard let weakSelf = self, !op.isCancelled else {
                    return
                }
                weakSelf.assets = assets
                weakSelf.users = contacts
                weakSelf.conversationsByName = conversationsByName
                weakSelf.conversationsByMessage = conversationsByMessage
                weakSelf.tableView.reloadData()
                weakSelf.lastKeyword = keyword
            }
        }
        queue.addOperation(op)
    }
    
    func prepareForReuse() {
        searchTextField.text = nil
        showRecentApps()
        assets = []
        users = []
        conversationsByName = []
        conversationsByMessage = []
        tableView.reloadData()
        lastKeyword = nil
    }
    
    func willHide() {
        searchNumberRequest?.cancel()
        searchNumberRequest = nil
    }
    
}

extension SearchViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .searchNumber:
            return shouldShowSearchNumber ? 1 : 0
        case .asset:
            return min(resultLimit, assets.count)
        case .user:
            return min(resultLimit, users.count)
        case .group:
            return min(resultLimit, conversationsByName.count)
        case .conversation:
            return min(resultLimit, conversationsByMessage.count)
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .searchNumber:
            let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.search_number, for: indexPath)!
            if let keyword = searchTextField.text {
                cell.render(number: keyword)
            }
            cell.isBusy = searchNumberRequest != nil
            return cell
        case .asset:
            let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.asset, for: indexPath)!
            let result = assets[indexPath.row]
            cell.render(asset: result.asset, attributedSymbol: result.attributedSymbol)
            return cell
        case .user:
            let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.search_result, for: indexPath)!
            cell.render(result: users[indexPath.row])
            return cell
        case .group:
            let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.search_result, for: indexPath)!
            cell.render(result: conversationsByName[indexPath.row])
            return cell
        case .conversation:
            let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.search_result, for: indexPath)!
            cell.render(result: conversationsByMessage[indexPath.row])
            return cell
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
}

extension SearchViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .searchNumber:
            return UITableView.automaticDimension
        case .asset, .user, .group, .conversation:
            return SearchResultCell.height
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = Section(rawValue: section)!
        switch section {
        case .searchNumber:
            return .leastNormalMagnitude
        case .asset, .user, .group, .conversation:
            if isEmptySection(section) {
                return .leastNormalMagnitude
            } else {
                return SearchHeaderView.height(isFirstSection: isFirstSection(section))
            }
        }
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let section = Section(rawValue: section)!
        switch section {
        case .searchNumber:
            return .leastNormalMagnitude
        case .asset, .user, .group, .conversation:
            return isEmptySection(section) ? .leastNormalMagnitude : SearchFooterView.height
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = Section(rawValue: section)!
        switch section {
        case .searchNumber:
            return nil
        case .asset, .user, .group, .conversation:
            if isEmptySection(section) {
                return nil
            } else {
                let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ReuseId.header) as! SearchHeaderView
                view.isFirstSection = isFirstSection(section)
                view.label.text = section.title
                view.button.isHidden = models(forSection: section).count <= resultLimit
                view.section = section.rawValue
                view.delegate = self
                return view
            }
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let section = Section(rawValue: section)!
        switch section {
        case .searchNumber:
            return nil
        case .asset, .user, .group, .conversation:
            if isEmptySection(section) {
                return nil
            } else {
                return tableView.dequeueReusableHeaderFooterView(withIdentifier: ReuseId.footer)
            }
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        searchTextField.resignFirstResponder()
        switch Section(rawValue: indexPath.section)! {
        case .searchNumber:
            searchNumber()
        case .asset:
            pushAssetViewController(asset: assets[indexPath.row].asset)
        case .user:
            pushViewController(keyword: keyword, result: users[indexPath.row])
        case .group:
            pushViewController(keyword: keyword, result: conversationsByName[indexPath.row])
        case .conversation:
            pushViewController(keyword: keyword, result: conversationsByMessage[indexPath.row])
        }
    }
    
}

extension SearchViewController: SearchHeaderViewDelegate {
    
    func searchHeaderViewDidSendMoreAction(_ view: SearchHeaderView) {
        guard let sectionValue = view.section, let section = Section(rawValue: sectionValue) else {
            return
        }
        let vc = R.storyboard.home.search_category()!
        switch section {
        case .searchNumber:
            return
        case .asset:
            vc.category = .asset
        case .user:
            vc.category = .user
        case .group:
            vc.category = .conversationsByName
        case .conversation:
            vc.category = .conversationsByMessage
        }
        vc.inheritedKeyword = keyword
        searchTextField.resignFirstResponder()
        searchNavigationController?.pushViewController(vc, animated: true)
    }
    
}

extension SearchViewController {
    
    enum ReuseId {
        static let header = "header"
        static let footer = "footer"
    }
    
    enum Section: Int, CaseIterable {
        case searchNumber = 0
        case asset
        case user
        case group
        case conversation
        
        var title: String? {
            switch self {
            case .searchNumber:
                return nil
            case .asset:
                return R.string.localizable.search_section_title_asset()
            case .user:
                return R.string.localizable.search_section_title_user()
            case .group:
                return R.string.localizable.search_section_title_conversation_by_name()
            case .conversation:
                return R.string.localizable.search_section_title_conversation_by_message()
            }
        }
    }
    
    private func showSearchResults() {
        tableView.isHidden = false
        recentAppsContainerView.isHidden = true
    }
    
    private func showRecentApps() {
        tableView.isHidden = true
        recentAppsViewController?.reloadIfNeeded()
        recentAppsContainerView.isHidden = false
    }
    
    private func models(forSection section: Section) -> [Any] {
        switch section {
        case .searchNumber:
            return []
        case .asset:
            return assets
        case .user:
            return users
        case .group:
            return conversationsByName
        case .conversation:
            return conversationsByMessage
        }
    }
    
    private func isEmptySection(_ section: Section) -> Bool {
        switch section {
        case .searchNumber:
            return !shouldShowSearchNumber
        case .asset, .user, .group, .conversation:
            return models(forSection: section).isEmpty
        }
    }
    
    private func isFirstSection(_ section: Section) -> Bool {
        switch section {
        case .searchNumber:
            return shouldShowSearchNumber
        case .asset:
            return !shouldShowSearchNumber
        case .user:
            return !shouldShowSearchNumber && assets.isEmpty
        case .group:
            return !shouldShowSearchNumber && assets.isEmpty && users.isEmpty
        case .conversation:
            return !shouldShowSearchNumber && assets.isEmpty && users.isEmpty && conversationsByName.isEmpty
        }
    }
    
    private func searchNumber() {
        guard let keyword = self.keyword else {
            return
        }
        searchNumberRequest?.cancel()
        searchNumberCell?.isBusy = true
        searchNumberRequest = UserAPI.shared.search(keyword: keyword.trimmed) { [weak self] (result) in
            guard let weakSelf = self, weakSelf.searchNumberRequest != nil else {
                return
            }
            weakSelf.searchNumberCell?.isBusy = false
            weakSelf.searchNumberRequest = nil
            switch result {
            case let .success(user):
                UserDAO.shared.updateUsers(users: [user])
                weakSelf.userWindow
                    .updateUser(user: UserItem.createUser(from: user), refreshUser: false)
                    .presentView()
            case let .failure(error):
                let text = error.code == 404 ? Localized.CONTACT_SEARCH_NOT_FOUND : error.localizedDescription
                showHud(style: .error, text: text)
            }
        }
    }
    
}
