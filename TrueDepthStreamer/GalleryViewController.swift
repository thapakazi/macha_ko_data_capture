/*
See LICENSE folder for this sample's licensing information.

Abstract:
Gallery view controller for displaying and managing captured data.
*/

import UIKit

class GalleryViewController: UIViewController {
    
    private var tableView: UITableView!
    private var emptyStateLabel: UILabel!
    
    private var captures: [CaptureData] = []
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCaptures()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCaptures() // Refresh when returning to gallery
    }
    
    private func setupUI() {
        title = "Gallery"
        view.backgroundColor = .black
        
        // Create table view
        tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .black
        tableView.separatorColor = .darkGray
        tableView.register(CaptureTableViewCell.self, forCellReuseIdentifier: "CaptureCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create empty state label
        emptyStateLabel = UILabel()
        emptyStateLabel.text = "No captures yet\nTap Capture to get started"
        emptyStateLabel.textColor = .white
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.font = UIFont.systemFont(ofSize: 18)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func loadCaptures() {
        captures = CaptureManager.shared.getAllCaptures()
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.emptyStateLabel.isHidden = !self.captures.isEmpty
            self.tableView.isHidden = self.captures.isEmpty
        }
    }
    
    private func shareCapture(_ capture: CaptureData) {
        var activityItems: [Any] = []
        var description = "TrueDepth Capture from \(dateFormatter.string(from: capture.date))\n\n"
        
        // Add calibration JSON
        if let jsonPath = capture.calibrationJSONPath,
           let jsonURL = CaptureManager.shared.getFileURL(for: jsonPath),
           CaptureManager.shared.fileExists(at: jsonPath) {
            activityItems.append(jsonURL)
            description += "• Calibration JSON\n"
        }
        
        // Add TIFF file
        if let tiffPath = capture.depthTIFFPath,
           let tiffURL = CaptureManager.shared.getFileURL(for: tiffPath),
           CaptureManager.shared.fileExists(at: tiffPath) {
            activityItems.append(tiffURL)
            description += "• 16-bit Depth TIFF\n"
        }
        
        // Add binary depth data
        if let binaryPath = capture.depthBinaryPath,
           let binaryURL = CaptureManager.shared.getFileURL(for: binaryPath),
           CaptureManager.shared.fileExists(at: binaryPath) {
            activityItems.append(binaryURL)
            description += "• Raw Binary Depth\n"
        }
        
        // Add metadata
        if let metadataPath = capture.metadataJSONPath,
           let metadataURL = CaptureManager.shared.getFileURL(for: metadataPath),
           CaptureManager.shared.fileExists(at: metadataPath) {
            activityItems.append(metadataURL)
            description += "• Metadata JSON\n"
        }
        
        activityItems.insert(description, at: 0)
        
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // For iPad
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(activityVC, animated: true)
    }
    
    private func deleteCapture(at indexPath: IndexPath) {
        let capture = captures[indexPath.row]
        
        let alert = UIAlertController(title: "Delete Capture", 
                                    message: "This will permanently delete the capture and all associated files.", 
                                    preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            // Delete files
            self.deleteFiles(for: capture)
            
            // Remove from manager
            CaptureManager.shared.deleteCapture(withID: capture.id)
            
            // Update UI
            self.captures.remove(at: indexPath.row)
            self.tableView.deleteRows(at: [indexPath], with: .fade)
            
            if self.captures.isEmpty {
                self.emptyStateLabel.isHidden = false
                self.tableView.isHidden = true
            }
        })
        
        present(alert, animated: true)
    }
    
    private func deleteFiles(for capture: CaptureData) {
        let filePaths = [
            capture.calibrationJSONPath,
            capture.depthTIFFPath,
            capture.depthBinaryPath,
            capture.metadataJSONPath
        ]
        
        for path in filePaths {
            if let path = path {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension GalleryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return captures.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CaptureCell", for: indexPath) as! CaptureTableViewCell
        let capture = captures[indexPath.row]
        cell.configure(with: capture, dateFormatter: dateFormatter)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension GalleryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let capture = captures[indexPath.row]
        let detailVC = CaptureDetailViewController()
        detailVC.capture = capture
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let capture = captures[indexPath.row]
        
        let shareAction = UIContextualAction(style: .normal, title: "Share") { _, _, completion in
            self.shareCapture(capture)
            completion(true)
        }
        shareAction.backgroundColor = .systemBlue
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
            self.deleteCapture(at: indexPath)
            completion(true)
        }
        
        return UISwipeActionsConfiguration(actions: [deleteAction, shareAction])
    }
}

// MARK: - CaptureTableViewCell
class CaptureTableViewCell: UITableViewCell {
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let fileCountLabel = UILabel()
    private let statusIndicator = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .black
        contentView.backgroundColor = .black
        
        titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        titleLabel.textColor = .white
        
        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = .lightGray
        
        fileCountLabel.font = UIFont.systemFont(ofSize: 12)
        fileCountLabel.textColor = .systemBlue
        
        statusIndicator.layer.cornerRadius = 4
        statusIndicator.backgroundColor = .systemGreen
        
        [titleLabel, subtitleLabel, fileCountLabel, statusIndicator].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            statusIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusIndicator.widthAnchor.constraint(equalToConstant: 8),
            statusIndicator.heightAnchor.constraint(equalToConstant: 8),
            
            titleLabel.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: fileCountLabel.leadingAnchor, constant: -8),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            
            fileCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            fileCountLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    func configure(with capture: CaptureData, dateFormatter: DateFormatter) {
        titleLabel.text = "Capture \(Int(capture.timestamp))"
        subtitleLabel.text = dateFormatter.string(from: capture.date)
        
        // Count available files
        var fileCount = 0
        if CaptureManager.shared.fileExists(at: capture.calibrationJSONPath) { fileCount += 1 }
        if CaptureManager.shared.fileExists(at: capture.depthTIFFPath) { fileCount += 1 }
        if CaptureManager.shared.fileExists(at: capture.depthBinaryPath) { fileCount += 1 }
        if CaptureManager.shared.fileExists(at: capture.metadataJSONPath) { fileCount += 1 }
        
        fileCountLabel.text = "\(fileCount) files"
        
        // Status indicator (green if all files exist)
        statusIndicator.backgroundColor = fileCount > 0 ? .systemGreen : .systemRed
    }
}