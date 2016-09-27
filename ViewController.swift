//
//  ViewController.swift
//  Mosaic
//
//  Created by Bernardo Santana on 9/27/16.
//  Copyright © 2016 Bernardo Santana. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    let NUM_TILES = 1000
    let blackImage = UIImage(named: "black.png")
    let redImage = UIImage(named: "red.png")
    var tiles = [UIImageView?]()
    var images = [UIImage]()
    var tilesPerRow:Int = 0
    var tileHeight:CGFloat = 0
    
    enum TileColor {
        case red
        case black
    }
    
    override func viewDidAppear(_ animated: Bool) {
        (tilesPerRow,tileHeight) = gridDimensionsFor(nTiles: NUM_TILES)
        tiles = [UIImageView?](repeating: nil, count: NUM_TILES)
        images = [UIImage](repeating: UIImage(named: "black.png")!, count: 56000)
        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.drawFrame), userInfo: nil, repeats: true)
        
    }
    
    var currentColor:TileColor = .red
    
    func drawFrame() {
        if currentColor == .red {
            setTiles(.red)
            currentColor = .black
        } else {
            setTiles(.black)
            currentColor = .red
        }
    }
    
    func setTiles(_ colorOption:TileColor) {
        var color: UIImage?
        switch colorOption {
        case .red:
            color = redImage
        case .black:
            color = blackImage
        }
        
        for i in 0..<NUM_TILES {
            if tiles[i] == nil {
                let tile = UIImageView(image:color!)
                tiles[i] = tile
                tile.frame = frameForTile(atIndex: i)
                view.addSubview(tile)
            } else {
                tiles[i]?.image = nil
                tiles[i]?.image = color!
            }
        }
    }
    
    func gridDimensionsFor(nTiles:Int) -> (Int,CGFloat){
        let area = view.frame.width * view.frame.height / CGFloat(nTiles)
        let maxSide = sqrt(area)
        let nTilesH = ceil(view.frame.width / maxSide)
        return (Int(nTilesH) , view.frame.width / nTilesH)
    }
    
    func frameForTile(atIndex idx:Int) -> CGRect {
        return CGRect(x: CGFloat(idx%tilesPerRow)*tileHeight, y: CGFloat(idx/tilesPerRow)*tileHeight, width: tileHeight, height: tileHeight)
    }



}

