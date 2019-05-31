import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController {

    // MARK: Outlets
    @IBOutlet var sceneView: ARSCNView!
    
    // MARK: - Properties
    let configuration = ARWorldTrackingConfiguration()
    
    let touchMinDistanceSquare = CGFloat(40 * 40)
    var lastObjectPlacePoint: CGPoint?
    
    var selectedNode: SCNNode?
    
    var placedNodes = [SCNNode]() {
        didSet {
            print(#function, #line, placedNodes.count)
        }
    }
    var planeNodes = [SCNNode]() {
        didSet {
            print(#function, #line, planeNodes.count)
        }
    }
    
    var showPlaneOverlay = false {
        didSet {
            planeNodes.forEach { $0.isHidden = !showPlaneOverlay }
        }
    }
    
    enum ObjectPlacementMode {
        case freeform, plane, image
    }
    
    var objectMode: ObjectPlacementMode = .freeform {
        didSet {
            reloadConfiguration(removeAnchors: false)
        }
    }
    
    // MARK: - Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration(removeAnchors: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    func reloadConfiguration(removeAnchors: Bool = true) {
        let images = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil)
        configuration.detectionImages = objectMode == .image ? images : nil
        configuration.planeDetection = [.horizontal, .vertical]
        
        let options: ARSession.RunOptions
        
        if removeAnchors {
            options = [.removeExistingAnchors]
            
            planeNodes.forEach { $0.removeFromParentNode() }
            planeNodes.removeAll()
            
            placedNodes.forEach { $0.removeFromParentNode() }
            placedNodes.removeAll()
            
        } else {
            options = []
        }
        
        sceneView.session.run(configuration, options: options)
    }
    
    @IBAction func animationControl(_ sender: UISegmentedControl) {
        
        switch sender.selectedSegmentIndex {
        case 0:
            guard let lastNode = placedNodes.last else { return }
            lastNode.isPaused = true
            lastNode.enumerateHierarchy { node, _ in
                for key in node.animationKeys {
                    let player = node.animationPlayer(forKey: key)!
                    
                    let animation = player.animation
                    
                    let duration = animation.duration
                    let caAnimation = CAAnimation(scnAnimation: animation)
                    caAnimation.timeOffset = duration / 2
                    caAnimation.fillMode = .forwards
                    caAnimation.isRemovedOnCompletion = false
                    
                    let animationGroup = CAAnimationGroup()
                    animationGroup.animations = [caAnimation]
                    animationGroup.duration = duration / 2
                    animationGroup.fillMode = .forwards
                    animationGroup.isRemovedOnCompletion = false
                    animationGroup.repeatCount = .greatestFiniteMagnitude
                    
                    let scnAnimation = SCNAnimation(caAnimation: animationGroup)
                    let newPlayer = SCNAnimationPlayer(animation: scnAnimation)
                    node.addAnimationPlayer(newPlayer, forKey: key)
                    newPlayer.play()
                    print(#line, #function, key, caAnimation.timeOffset, animationGroup.duration, newPlayer.paused)
                    
                }
            }
            break
        case 1:
            placedNodes.last?.isPaused = false
            break
        case 2:
            break
        default:
            break
        }
    }

    @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            objectMode = .freeform
            showPlaneOverlay = false
        case 1:
            objectMode = .plane
            showPlaneOverlay = true
        case 2:
            objectMode = .image
            showPlaneOverlay = false
        default:
            break
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOptions" {
            let optionsViewController = segue.destination as! OptionsContainerViewController
            optionsViewController.delegate = self
        }
    }
}

extension ViewController: OptionsViewControllerDelegate {
    
    func objectSelected(node: SCNNode) {
        dismiss(animated: true, completion: nil)
        selectedNode = node
    }
    
    func togglePlaneVisualization() {
        dismiss(animated: true, completion: nil)
        showPlaneOverlay.toggle()
    }
    
    func undoLastObject() {
        guard let lastNode = placedNodes.last else { return }
        lastNode.removeFromParentNode()
        placedNodes.removeLast()
    }
    
    func resetScene() {
        dismiss(animated: true, completion: nil)
        reloadConfiguration()
    }
}

// MARK: - Touches
extension ViewController {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let selectedNode = selectedNode else { return }
        guard let touch = touches.first else { return }
        
        switch objectMode {
        case .freeform:
            addNodeInFront(selectedNode)
        case .image:
            break
        case .plane:
            let point = touch.location(in: sceneView)
            addNode(selectedNode, at: point)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard objectMode == .plane else { return }
        guard let selectedNode = selectedNode else { return }
        guard let touch = touches.first else { return }
        guard let lastTouchPoint = lastObjectPlacePoint else { return }
        
        let newTouchPoint = touch.location(in: sceneView)
        let x = newTouchPoint.x - lastTouchPoint.x
        let y = newTouchPoint.y - lastTouchPoint.y
        let distanceSquare = x * x + y * y
        if touchMinDistanceSquare < distanceSquare {
            addNode(selectedNode, at: newTouchPoint)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        lastObjectPlacePoint = nil
    }
}

// MARK: - Object Placement Methods
extension ViewController {
    func addNode(_ node: SCNNode, to parentNode: SCNNode) {
        let cloneNode = node.clone()
        parentNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
    }
    
    func addNode(_ node: SCNNode, at point: CGPoint) {
        guard let result = sceneView.hitTest(point, types: [.existingPlaneUsingExtent]).first else {
            return
        }
        
        let transform = result.worldTransform
        node.simdTransform = transform
        addNodeToSceneRoot(node)
        lastObjectPlacePoint = point
    }
    
    func addNodeToSceneRoot(_ node: SCNNode) {
        addNode(node, to: sceneView.scene.rootNode)
    }
    
    func addNodeInFront(_ node: SCNNode) {
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        var translation = matrix_identity_float4x4
        translation.columns.3.z = -0.2
        node.simdTransform = matrix_multiply(
            currentFrame.camera.transform,
            translation
        )
        
        addNodeToSceneRoot(node)
    }
    
    func createFloor(planeAnchor: ARPlaneAnchor) -> SCNNode {
        let extent = planeAnchor.extent
        let width = CGFloat(extent.x)
        let height = CGFloat(extent.z)
        let plane = SCNPlane(width: width, height: height)
        plane.firstMaterial?.diffuse.contents = #colorLiteral(red: 0, green: 0.4784313725, blue: 1, alpha: 1)
        let floor = SCNNode(geometry: plane)
        
        floor.eulerAngles.x = -.pi / 2
        floor.opacity = 0.25
        
        return floor
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let floor = createFloor(planeAnchor: anchor)
        floor.isHidden = !showPlaneOverlay
        node.addChildNode(floor)
        planeNodes.append(floor)
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) {
        guard let selectedNode = selectedNode else { return }
        addNode(selectedNode, to: node)
    }
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let imageAnchor = anchor as? ARImageAnchor {
            nodeAdded(node, for: imageAnchor)
        } else if let planeAnchor = anchor as? ARPlaneAnchor {
            nodeAdded(node, for: planeAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        guard let planeNode = node.childNodes.first else { return }
        guard let plane = planeNode.geometry as? SCNPlane else { return }
        
        let center = planeAnchor.center
        planeNode.position = SCNVector3(center.x, 0, center.z)
        
        let extent = planeAnchor.extent
        plane.width = CGFloat(extent.x)
        plane.height = CGFloat(extent.z)
    }
}
