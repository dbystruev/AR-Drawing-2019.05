import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController {

    // MARK: Outlets
    @IBOutlet var sceneView: ARSCNView!
    
    // MARK: - Properties
    let configuration = ARWorldTrackingConfiguration()
    
    var selectedNode: SCNNode?
    
    var placedNodes = [SCNNode]()
    var planeNodes = [SCNNode]()
    
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
            reloadConfiguration()
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
        reloadConfiguration()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    func reloadConfiguration() {
        let images = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil)
        configuration.detectionImages = objectMode == .image ? images : nil
        configuration.planeDetection = [.horizontal]
        sceneView.session.run(configuration)
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
        
    }
    
    func resetScene() {
        dismiss(animated: true, completion: nil)
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
            break
        }
    }
}

// MARK: - Object Placement Methods
extension ViewController {
    func addNode(_ node: SCNNode, to parentNode: SCNNode) {
        let cloneNode = node.clone()
        parentNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
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
