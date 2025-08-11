//
//  GameScene.swift
//  flappy
//
//  Created by Bryce Harmon on 8/10/25.
//

import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Physics Categories
    // These bit masks identify different types of objects for collision detection
    struct PhysicsCategory {
        static let bird:   UInt32 = 1 << 0  // 0001
        static let pipe:   UInt32 = 1 << 1  // 0010
        static let gap:    UInt32 = 1 << 2  // 0100 (invisible scoring zone)
        static let ground: UInt32 = 1 << 3  // 1000
    }

    // MARK: - Game State
    enum State { case ready, playing, gameOver }
    private var state: State = .ready

    // MARK: - Core Game Nodes
    private var moving = SKNode()                 // Parent node for all scrolling elements
    private var bird = SKSpriteNode()
    private var scoreLabel = SKLabelNode(fontNamed: "Avenir-Heavy")
    private var gameOverLabel = SKLabelNode(fontNamed: "Avenir-Heavy")
    private var tapToRestartLabel = SKLabelNode(fontNamed: "Avenir-Heavy")

    // MARK: - Game Configuration Parameters
    // ============================================
    // ADJUST THESE VALUES TO FINE-TUNE GAMEPLAY
    // ============================================
    
    // Visual dimensions
    private let groundHeight: CGFloat = 96
    private let pipeWidth: CGFloat = 70
    
    // Gap between pipes - CRITICAL for difficulty
    // Original Flappy Bird: ~120-140 pixels
    // Increase this value to make the game easier
    private var gapHeight: CGFloat {
        max(160, size.height * 0.25)  // Minimum 160px or 25% of screen height
    }
    
    // Horizontal scrolling speed (points per second)
    // Lower = easier (more time to react)
    // Original Flappy Bird: ~150-180
    private let scrollSpeed: CGFloat = 140
    
    // Time between pipe spawns (seconds)
    // Higher = easier (more space between pipes)
    private let pipeSpawnInterval: TimeInterval = 2.0
    
    // Bird physics parameters
    private let birdSize = CGSize(width: 34, height: 34)  // Visual size
    private let birdCollisionRadius: CGFloat = 15         // Physics collision size (smaller = more forgiving)
    
    // MARK: - Critical Physics Values
    // ============================================
    // THESE ARE THE MOST IMPORTANT FOR GAME FEEL
    // ============================================
    
    // Gravity strength (negative = downward)
    // Original Flappy Bird: around -15 to -20
    // More negative = bird falls faster
    private let gravityStrength: CGFloat = -5.0
    
    // Jump velocity when tapping
    // Original Flappy Bird: around 200-300
    // Higher = stronger jumps (but harder to control)
    // This is the MOST CRITICAL value for gameplay
    private let flapVelocity: CGFloat = 200
    
    // Maximum fall speed (terminal velocity)
    // Prevents bird from falling too fast
    // Lower = more floaty feeling
    private let maxFallSpeed: CGFloat = -300
    
    // Maximum rise speed (optional cap on upward movement)
    // Set to nil for no limit
    private let maxRiseSpeed: CGFloat? = nil
    
    // Action key for spawning pipes
    private var spawnActionKey = "spawnPipes"

    // Score tracking
    private var score = 0 {
        didSet { scoreLabel.text = "\(score)" }
    }

    // MARK: - Scene Lifecycle
    override func didMove(to view: SKView) {
        // Set up the physics world
        backgroundColor = .systemTeal
        
        // GRAVITY: The constant downward force
        // Adjust gravityStrength constant above to change
        physicsWorld.gravity = CGVector(dx: 0, dy: gravityStrength)
        physicsWorld.contactDelegate = self

        // Set up the scene
        addChild(moving)  // Add the scrolling parent node
        setupHUD()
        setupGround()
        setupBird()
        showReadyHint()
    }

    // MARK: - Setup Methods
    
    private func setupHUD() {
        // Score display at top of screen
        scoreLabel.fontSize = 44
        scoreLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 80)
        scoreLabel.zPosition = 100  // Always on top
        scoreLabel.text = "0"
        addChild(scoreLabel)
    }

    private func setupGround() {
        // Visual ground sprite
        let ground = SKSpriteNode(color: .brown, size: CGSize(width: size.width * 2, height: groundHeight))
        ground.position = CGPoint(x: size.width / 2, y: groundHeight / 2)
        ground.zPosition = 5
        addChild(ground)

        // Physics body for ground collision
        // Made extra wide to ensure bird always hits it
        let groundBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: groundHeight))
        groundBody.isDynamic = false  // Ground doesn't move
        groundBody.categoryBitMask = PhysicsCategory.ground
        groundBody.collisionBitMask = PhysicsCategory.bird
        groundBody.contactTestBitMask = PhysicsCategory.bird
        ground.physicsBody = groundBody
    }

    private func setupBird() {
        // Create bird sprite
        bird = SKSpriteNode(color: .yellow, size: birdSize)
        
        // Starting position (left third of screen, 60% up)
        bird.position = CGPoint(x: size.width * 0.35, y: size.height * 0.6)
        bird.zPosition = 10
        
        // Physics body (circle is more forgiving than rectangle)
        // Collision radius is smaller than visual size for better game feel
        bird.physicsBody = SKPhysicsBody(circleOfRadius: birdCollisionRadius)
        bird.physicsBody?.isDynamic = false   // Becomes true when game starts
        bird.physicsBody?.allowsRotation = false  // Bird doesn't spin
        
        // Set up collision detection
        bird.physicsBody?.categoryBitMask = PhysicsCategory.bird
        bird.physicsBody?.collisionBitMask = PhysicsCategory.pipe | PhysicsCategory.ground
        bird.physicsBody?.contactTestBitMask = PhysicsCategory.pipe | PhysicsCategory.ground | PhysicsCategory.gap
        
        addChild(bird)
    }

    private func showReadyHint() {
        let hint = SKLabelNode(fontNamed: "Avenir-Heavy")
        hint.text = "Tap to Flap"
        hint.fontSize = 34
        hint.zPosition = 100
        hint.position = CGPoint(x: frame.midX, y: frame.midY)
        hint.name = "hint"
        addChild(hint)
    }

    // MARK: - Game Flow Methods
    
    private func startGame() {
        state = .playing
        score = 0
        
        // Clean up UI
        childNode(withName: "hint")?.removeFromParent()
        gameOverLabel.removeFromParent()
        tapToRestartLabel.removeFromParent()

        // Activate bird physics
        bird.physicsBody?.isDynamic = true
        bird.physicsBody?.velocity = .zero
        
        // Give initial flap
        flap()

        // Start spawning pipes at regular intervals
        let spawn = SKAction.run { [weak self] in self?.spawnPipes() }
        let wait = SKAction.wait(forDuration: pipeSpawnInterval)
        let seq = SKAction.sequence([spawn, wait])
        run(SKAction.repeatForever(seq), withKey: spawnActionKey)
    }

    private func gameOver() {
        guard state == .playing else { return }
        state = .gameOver
        
        // Stop spawning new pipes
        removeAction(forKey: spawnActionKey)
        
        // Stop all scrolling
        moving.removeAllActions()
        moving.speed = 0

        // Show game over UI
        gameOverLabel.text = "Game Over"
        gameOverLabel.fontSize = 56
        gameOverLabel.position = CGPoint(x: frame.midX, y: frame.midY + 20)
        gameOverLabel.zPosition = 200

        tapToRestartLabel.text = "Tap to Restart"
        tapToRestartLabel.fontSize = 28
        tapToRestartLabel.position = CGPoint(x: frame.midX, y: frame.midY - 40)
        tapToRestartLabel.zPosition = 200

        addChild(gameOverLabel)
        addChild(tapToRestartLabel)
    }

    private func reset() {
        // Clean up all pipes and gaps
        moving.removeAllChildren()
        moving.removeAllActions()
        moving.speed = 1.0

        // Reset bird to starting position
        bird.position = CGPoint(x: size.width * 0.35, y: size.height * 0.6)
        bird.physicsBody?.velocity = .zero
        bird.zRotation = 0
        bird.physicsBody?.isDynamic = false  // Disable physics until game starts

        // Reset score and UI
        score = 0
        childNode(withName: "hint")?.removeFromParent()
        gameOverLabel.removeFromParent()
        tapToRestartLabel.removeFromParent()

        // Return to ready state
        state = .ready
        showReadyHint()
    }

    // MARK: - Pipe Generation
    
    private func spawnPipes() {
        // Calculate valid range for pipe gap center
        // Gap must not be too high or too low
        let centerMin = groundHeight + gapHeight/2 + 20   // Minimum distance from ground
        let centerMax = size.height - gapHeight/2 - 50    // Minimum distance from top
        
        // Safety check to prevent crash if gap is too large
        guard centerMin < centerMax else {
            print("Warning: Gap too large for screen size!")
            return
        }
        
        // Random vertical position for gap center
        let centerY = CGFloat.random(in: centerMin...centerMax)

        // Calculate pipe heights
        let bottomHeight = max(10, centerY - gapHeight/2 - groundHeight)
        let topHeight = max(10, size.height - (centerY + gapHeight/2))

        // Starting position (off right edge of screen)
        let startX = size.width + pipeWidth/2

        // BOTTOM PIPE
        let bottomPipe = SKSpriteNode(color: .green, size: CGSize(width: pipeWidth, height: bottomHeight))
        bottomPipe.anchorPoint = CGPoint(x: 0.5, y: 0.0)  // Anchor at bottom center
        bottomPipe.position = CGPoint(x: startX, y: groundHeight)
        bottomPipe.zPosition = 8
        
        // Physics for bottom pipe
        bottomPipe.physicsBody = SKPhysicsBody(
            rectangleOf: bottomPipe.size,
            center: CGPoint(x: 0, y: bottomPipe.size.height/2)
        )
        bottomPipe.physicsBody?.isDynamic = false
        bottomPipe.physicsBody?.categoryBitMask = PhysicsCategory.pipe
        bottomPipe.physicsBody?.contactTestBitMask = PhysicsCategory.bird

        // TOP PIPE
        let topPipe = SKSpriteNode(color: .green, size: CGSize(width: pipeWidth, height: topHeight))
        topPipe.anchorPoint = CGPoint(x: 0.5, y: 1.0)  // Anchor at top center
        topPipe.position = CGPoint(x: startX, y: size.height)
        topPipe.zPosition = 8
        
        // Physics for top pipe
        topPipe.physicsBody = SKPhysicsBody(
            rectangleOf: topPipe.size,
            center: CGPoint(x: 0, y: -topPipe.size.height/2)
        )
        topPipe.physicsBody?.isDynamic = false
        topPipe.physicsBody?.categoryBitMask = PhysicsCategory.pipe
        topPipe.physicsBody?.contactTestBitMask = PhysicsCategory.bird

        // GAP NODE (invisible scoring trigger)
        let gapNode = SKNode()
        gapNode.position = CGPoint(x: startX, y: centerY)
        gapNode.zPosition = 7
        
        // Physics body for gap (bird scores when passing through)
        gapNode.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: pipeWidth, height: gapHeight))
        gapNode.physicsBody?.isDynamic = false
        gapNode.physicsBody?.categoryBitMask = PhysicsCategory.gap
        gapNode.physicsBody?.contactTestBitMask = PhysicsCategory.bird

        // Create scrolling action
        let distance = size.width + pipeWidth + 100  // Total distance to travel
        let duration = TimeInterval(distance / scrollSpeed)
        let move = SKAction.moveBy(x: -distance, y: 0, duration: duration)
        let remove = SKAction.removeFromParent()
        let seq = SKAction.sequence([move, remove])

        // Add all elements to scrolling parent and start movement
        [bottomPipe, topPipe, gapNode].forEach {
            moving.addChild($0)
            $0.run(seq)
        }
    }

    // MARK: - Input Handling
    
    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleInput()
    }
    #elseif os(macOS)
    override func mouseDown(with event: NSEvent) {
        handleInput()
    }
    #endif
    
    private func handleInput() {
        switch state {
        case .ready:
            startGame()
        case .playing:
            flap()
        case .gameOver:
            reset()
        }
    }

    // MARK: - Bird Movement
    
    private func flap() {
        guard state == .playing else { return }
        
        // THE MOST IMPORTANT METHOD IN THE GAME!
        // This controls how the bird responds to taps
        
        // Option 1: Set velocity directly (more consistent)
        // This replaces any existing velocity with the flap velocity
        bird.physicsBody?.velocity.dy = flapVelocity
        
        // Option 2: Apply impulse (more physics-based)
        // Uncomment this and comment out Option 1 to try it
        // bird.physicsBody?.velocity.dy = 0  // Reset first for consistency
        // bird.physicsBody?.applyImpulse(CGVector(dx: 0, dy: flapVelocity * 0.5))
        
        // Option 3: Additive velocity (builds on existing momentum)
        // Uncomment this and comment out Option 1 to try it
        // let currentVY = bird.physicsBody?.velocity.dy ?? 0
        // bird.physicsBody?.velocity.dy = min(currentVY + flapVelocity, flapVelocity)
    }

    // MARK: - Collision Detection
    
    func didBegin(_ contact: SKPhysicsContact) {
        let contactMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if contactMask == (PhysicsCategory.bird | PhysicsCategory.gap) {
            // Bird passed through gap - score!
            score += 1
            
        } else if (contactMask & PhysicsCategory.pipe != 0 && contactMask & PhysicsCategory.bird != 0) ||
                  (contactMask & PhysicsCategory.ground != 0 && contactMask & PhysicsCategory.bird != 0) {
            // Bird hit pipe or ground - game over
            gameOver()
        }
    }

    // MARK: - Frame Updates
    
    override func update(_ currentTime: TimeInterval) {
        guard state == .playing else { return }
        
        // VELOCITY CAPPING
        // Prevents bird from moving too fast in either direction
        if let velocity = bird.physicsBody?.velocity {
            // Cap falling speed (terminal velocity)
            if velocity.dy < maxFallSpeed {
                bird.physicsBody?.velocity.dy = maxFallSpeed
            }
            
            // Cap rising speed (optional)
            if let maxRise = maxRiseSpeed, velocity.dy > maxRise {
                bird.physicsBody?.velocity.dy = maxRise
            }
        }
        
        // BIRD ROTATION
        // Tilt bird based on vertical velocity for visual feedback
        if let vy = bird.physicsBody?.velocity.dy {
            // Map velocity to rotation angle
            // Adjust divisor to change rotation sensitivity
            let rotationFactor: CGFloat = 400.0  // Higher = less rotation
            bird.zRotation = vy / rotationFactor
            
            // Optional: Clamp rotation to maximum angle
            let maxRotation: CGFloat = 0.5  // radians
            bird.zRotation = max(-maxRotation, min(maxRotation, bird.zRotation))
        }
        
        // BOUNDARY CHECKS
        // Keep bird within screen bounds
        
        // Horizontal bounds (shouldn't normally be needed)
        bird.position.x = max(birdSize.width/2, min(size.width - birdSize.width/2, bird.position.x))
        
        // Ceiling check - prevent bird from flying off top
        if bird.position.y > size.height {
            bird.position.y = size.height
            bird.physicsBody?.velocity.dy = 0
        }
        
        // Ground check - trigger game over if too low
        if bird.position.y < groundHeight + birdCollisionRadius {
            gameOver()
        }
    }

    // MARK: - Layout Updates
    
    override func didChangeSize(_ oldSize: CGSize) {
        // Keep UI elements positioned correctly on rotation/resize
        scoreLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 80)
    }
}

// MARK: - Tuning Guide
/*
 FLAPPY BIRD PHYSICS TUNING GUIDE
 =================================
 
 To adjust difficulty and game feel, modify these key parameters:
 
 1. GRAVITY (gravityStrength: currently -9.0)
    - More negative = bird falls faster, harder game
    - Less negative = floatier feeling, easier to control
    - Typical range: -5.0 (easy) to -20.0 (very hard)
 
 2. FLAP STRENGTH (flapVelocity: currently 100)
    - Higher = bird jumps higher per tap
    - Lower = smaller, more controlled jumps
    - Must balance with gravity!
    - Typical range: 50 (tiny hops) to 300 (big jumps)
 
 3. GAP SIZE (gapHeight: currently 160px minimum)
    - Larger = easier to pass through
    - Smaller = requires more precision
    - Original Flappy Bird: ~120-140 pixels
 
 4. SCROLL SPEED (scrollSpeed: currently 140)
    - Faster = less reaction time
    - Slower = more time to plan
    - Typical range: 100 (easy) to 200 (hard)
 
 5. PIPE SPACING (pipeSpawnInterval: currently 2.0 seconds)
    - Longer = more space between obstacles
    - Shorter = more dense obstacles
    
 6. COLLISION RADIUS (birdCollisionRadius: currently 15)
    - Smaller = more forgiving hitbox
    - Should be slightly smaller than visual size
 
 BALANCING TIPS:
 - If bird can't stay up: Increase flapVelocity or decrease gravity
 - If bird jumps too high: Decrease flapVelocity or increase gravity
 - If game is too hard: Increase gapHeight or decrease scrollSpeed
 - For original Flappy Bird feel: gravity ~-15, flapVelocity ~250, gap ~130
 
 */
