/*
See LICENSE folder for this sample's licensing information.

Abstract:
Main tab bar controller that hosts camera and gallery views.
*/

import UIKit

class MainTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabBarAppearance()
    }
    
    private func setupTabBarAppearance() {
        tabBar.barStyle = .black
        tabBar.barTintColor = .black
        tabBar.tintColor = .systemBlue
        tabBar.unselectedItemTintColor = .lightGray
        
        // Set selected index to camera tab (first tab)
        selectedIndex = 0
    }
}