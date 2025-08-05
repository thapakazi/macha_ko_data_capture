/*
See LICENSE folder for this sample's licensing information.

Abstract:
Detail view controller for displaying individual capture information and files.
*/

import UIKit

class CaptureDetailViewController: UIViewController {
    
    var capture: CaptureData!
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateData()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        title = "Capture Details"
        
        // Add share button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareButtonTapped)
        )
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .fill
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func populateData() {
        // Capture Info Section
        stackView.addArrangedSubview(createSectionHeader("Capture Information"))
        stackView.addArrangedSubview(createInfoRow("Date", dateFormatter.string(from: capture.date)))
        stackView.addArrangedSubview(createInfoRow("ID", capture.id))
        stackView.addArrangedSubview(createInfoRow("Timestamp", String(capture.timestamp)))
        
        // Dimensions Section
        stackView.addArrangedSubview(createSectionHeader("Dimensions"))
        stackView.addArrangedSubview(createInfoRow("Video Size", "\(capture.videoDimensions.width) × \(capture.videoDimensions.height)"))
        stackView.addArrangedSubview(createInfoRow("Reference Size", "\(capture.referenceDimensions.width) × \(capture.referenceDimensions.height)"))
        stackView.addArrangedSubview(createInfoRow("Pixel Size", String(format: "%.6f mm", capture.pixelSize)))
        
        // Lens Distortion Section
        stackView.addArrangedSubview(createSectionHeader("Lens Distortion"))
        stackView.addArrangedSubview(createInfoRow("Center X", String(format: "%.2f", capture.lensDistortionCenter.x)))
        stackView.addArrangedSubview(createInfoRow("Center Y", String(format: "%.2f", capture.lensDistortionCenter.y)))
        
        // Intrinsic Matrix Section
        if let intrinsic = capture.intrinsicMatrix {
            stackView.addArrangedSubview(createSectionHeader("Intrinsic Matrix"))
            stackView.addArrangedSubview(createInfoRow("fx", String(format: "%.3f", intrinsic.fx)))
            stackView.addArrangedSubview(createInfoRow("fy", String(format: "%.3f", intrinsic.fy)))
            stackView.addArrangedSubview(createInfoRow("cx", String(format: "%.3f", intrinsic.cx)))
            stackView.addArrangedSubview(createInfoRow("cy", String(format: "%.3f", intrinsic.cy)))
            
            stackView.addArrangedSubview(createSectionHeader("Original Intrinsic Matrix"))
            stackView.addArrangedSubview(createInfoRow("fx_original", String(format: "%.3f", intrinsic.fx_original)))
            stackView.addArrangedSubview(createInfoRow("fy_original", String(format: "%.3f", intrinsic.fy_original)))
            stackView.addArrangedSubview(createInfoRow("cx_original", String(format: "%.3f", intrinsic.cx_original)))
            stackView.addArrangedSubview(createInfoRow("cy_original", String(format: "%.3f", intrinsic.cy_original)))
        }
        
        // Files Section
        stackView.addArrangedSubview(createSectionHeader("Files"))
        addFileRow("Calibration JSON", capture.calibrationJSONPath)
        addFileRow("Depth TIFF", capture.depthTIFFPath)
        addFileRow("Raw Binary Depth", capture.depthBinaryPath)
        addFileRow("Metadata JSON", capture.metadataJSONPath)
    }
    
    private func createSectionHeader(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.textColor = .systemBlue
        return label
    }
    
    private func createInfoRow(_ label: String, _ value: String) -> UIView {
        let containerView = UIView()
        
        let labelView = UILabel()
        labelView.text = label
        labelView.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        labelView.textColor = .white
        labelView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        let valueView = UILabel()
        valueView.text = value
        valueView.font = UIFont.systemFont(ofSize: 16)
        valueView.textColor = .lightGray
        valueView.numberOfLines = 0
        valueView.textAlignment = .right
        
        containerView.addSubview(labelView)
        containerView.addSubview(valueView)
        
        labelView.translatesAutoresizingMaskIntoConstraints = false
        valueView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            labelView.topAnchor.constraint(equalTo: containerView.topAnchor),
            labelView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            valueView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 16),
            valueView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            valueView.topAnchor.constraint(equalTo: containerView.topAnchor),
            valueView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    private func addFileRow(_ name: String, _ path: String?) {
        let containerView = UIView()
        
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        nameLabel.textColor = .white
        
        let statusView = UIView()
        statusView.layer.cornerRadius = 6
        
        let statusLabel = UILabel()
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textAlignment = .center
        
        if let path = path, CaptureManager.shared.fileExists(at: path) {
            statusView.backgroundColor = .systemGreen.withAlphaComponent(0.2)
            statusLabel.textColor = .systemGreen
            statusLabel.text = "Available"
            
            // Add tap gesture to share individual file
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(fileRowTapped(_:)))
            containerView.addGestureRecognizer(tapGesture)
            containerView.isUserInteractionEnabled = true
            containerView.tag = path.hashValue
        } else {
            statusView.backgroundColor = .systemRed.withAlphaComponent(0.2)
            statusLabel.textColor = .systemRed
            statusLabel.text = "Missing"
        }
        
        statusView.addSubview(statusLabel)
        containerView.addSubview(nameLabel)
        containerView.addSubview(statusView)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            statusView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            statusView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            statusView.widthAnchor.constraint(equalToConstant: 80),
            statusView.heightAnchor.constraint(equalToConstant: 28),
            
            statusLabel.centerXAnchor.constraint(equalTo: statusView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            
            containerView.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        stackView.addArrangedSubview(containerView)
    }
    
    @objc private func fileRowTapped(_ gesture: UITapGestureRecognizer) {
        guard let containerView = gesture.view else { return }
        
        // Find the file path based on the tag
        let filePaths = [
            capture.calibrationJSONPath,
            capture.depthTIFFPath,
            capture.depthBinaryPath,
            capture.metadataJSONPath
        ]
        
        for path in filePaths {
            if let path = path, path.hashValue == containerView.tag {
                if let fileURL = CaptureManager.shared.getFileURL(for: path) {
                    shareFile(fileURL)
                }
                break
            }
        }
    }
    
    private func shareFile(_ fileURL: URL) {
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func shareButtonTapped() {
        var activityItems: [Any] = []
        var description = "TrueDepth Capture from \(dateFormatter.string(from: capture.date))\n\n"
        
        let filePaths = [
            ("Calibration JSON", capture.calibrationJSONPath),
            ("16-bit Depth TIFF", capture.depthTIFFPath),
            ("Raw Binary Depth", capture.depthBinaryPath),
            ("Metadata JSON", capture.metadataJSONPath)
        ]
        
        for (name, path) in filePaths {
            if let path = path,
               let fileURL = CaptureManager.shared.getFileURL(for: path),
               CaptureManager.shared.fileExists(at: path) {
                activityItems.append(fileURL)
                description += "• \(name)\n"
            }
        }
        
        activityItems.insert(description, at: 0)
        
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityVC, animated: true)
    }
}