# Graph Report - /Users/alex/Documents/GitHub/FastViewer-Lite-for-macOS  (2026-07-29)

## Corpus Check
- 31 files · ~144,198 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 714 nodes · 1482 edges · 18 communities detected
- Extraction: 76% EXTRACTED · 24% INFERRED · 0% AMBIGUOUS · INFERRED: 361 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]

## God Nodes (most connected - your core abstractions)
1. `ViewController` - 128 edges
2. `SettingsManagerTests` - 77 edges
3. `ViewControllerTests` - 75 edges
4. `AppDelegate` - 52 edges
5. `FileListManagerTests` - 30 edges
6. `SettingsViewController` - 28 edges
7. `ImageCacheManagerTests` - 21 edges
8. `SettingsViewControllerTests` - 19 edges
9. `DraggableImageView` - 19 edges
10. `AboutViewControllerTests` - 17 edges

## Surprising Connections (you probably didn't know these)
- `AppDelegateTests` --inherits--> `XCTestCase`  [EXTRACTED]
  /Users/alex/Documents/GitHub/FastViewer-Lite-for-macOS/FastViewerTests/AppDelegateTests.swift →   _Bridges community 3 → community 7_
- `SettingsViewControllerTests` --inherits--> `XCTestCase`  [EXTRACTED]
  /Volumes/Samsung T7/! New Storage/Documents/Work/Pleeq Software/FastViewer Files/FastViewer/FastViewerTests/SettingsViewControllerTests.swift →   _Bridges community 7 → community 6_
- `SettingsManagerTests` --inherits--> `XCTestCase`  [EXTRACTED]
  /Users/alex/Documents/GitHub/FastViewer-Lite-for-macOS/FastViewerTests/SettingsManagerTests.swift →   _Bridges community 7 → community 2_
- `ImageCacheManagerTests` --inherits--> `XCTestCase`  [EXTRACTED]
  /Volumes/Samsung T7/! New Storage/Documents/Work/Pleeq Software/FastViewer Files/FastViewer/FastViewerTests/ImageCacheManagerTests.swift →   _Bridges community 7 → community 4_
- `DefaultFileAssociationManagerTests` --inherits--> `XCTestCase`  [EXTRACTED]
  /Volumes/Samsung T7/! New Storage/Documents/Work/Pleeq Software/FastViewer Files/FastViewer/FastViewerTests/DefaultFileAssociationManagerTests.swift →   _Bridges community 7 → community 9_

## Communities

### Community 0 - "Community 0"
Cohesion: 0.04
Nodes (6): DraggingDestinationHandler, name, NSDraggingDestination, NSView, PanningHandler, ViewController

### Community 1 - "Community 1"
Cohesion: 0.06
Nodes (5): DraggableView, DraggingDestinationHandler, NSDraggingInfo, MockDraggingInfo, ViewControllerTests

### Community 2 - "Community 2"
Cohesion: 0.03
Nodes (1): SettingsManagerTests

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (6): AppDelegate, AppDelegateTests, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, center

### Community 4 - "Community 4"
Cohesion: 0.07
Nodes (4): ImageCacheManager, ImageCacheManagerTests, ImageLoader, InFlightLoad

### Community 5 - "Community 5"
Cohesion: 0.09
Nodes (3): FileListManager, PreparedFileList, FileListManagerTests

### Community 6 - "Community 6"
Cohesion: 0.07
Nodes (2): SettingsViewController, SettingsViewControllerTests

### Community 7 - "Community 7"
Cohesion: 0.07
Nodes (4): AboutViewControllerTests, FolderAccessManager, FolderAccessManagerTests, XCTestCase

### Community 8 - "Community 8"
Cohesion: 0.09
Nodes (20): CaseIterable, DSStoreReader, FinderSortOrder, dateAdded, dateCreated, dateModified, kind, size (+12 more)

### Community 9 - "Community 9"
Cohesion: 0.08
Nodes (9): AssociationError, DefaultFileAssociationManager, ImageType, State, alreadyDefault, available, managedByFastViewer, DefaultFileAssociationManagerTests (+1 more)

### Community 10 - "Community 10"
Cohesion: 0.1
Nodes (6): ImageLoaderTests, ImageProcessingProtocol, ImageProcessingService, ServiceDelegate, NSObject, NSXPCListenerDelegate

### Community 11 - "Community 11"
Cohesion: 0.09
Nodes (4): DraggableImageView, PanningHandler, NonInteractiveImageView, NSImageView

### Community 12 - "Community 12"
Cohesion: 0.12
Nodes (5): AboutViewController, KeyboardShortcutsViewController, NSTableViewDataSource, NSTableViewDelegate, NSViewController

### Community 13 - "Community 13"
Cohesion: 0.17
Nodes (11): CursorType, closedHand, `default`, openHand, DragPreparationState, FileListCommit, currentIndex, keepCurrent (+3 more)

### Community 14 - "Community 14"
Cohesion: 0.27
Nodes (1): XPCImageLoader

### Community 15 - "Community 15"
Cohesion: 0.67
Nodes (1): ImageProcessingProtocol

### Community 16 - "Community 16"
Cohesion: 1.0
Nodes (0): 

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **23 isolated node(s):** `dateModified`, `dateCreated`, `dateAdded`, `kind`, `PanningHandler` (+18 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 16`** (1 nodes): `main.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 17`** (1 nodes): `main.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ViewController` connect `Community 0` to `Community 1`, `Community 3`, `Community 4`, `Community 5`, `Community 6`, `Community 11`, `Community 12`, `Community 13`?**
  _High betweenness centrality (0.330) - this node is a cross-community bridge._
- **Why does `ViewControllerTests` connect `Community 1` to `Community 0`, `Community 3`, `Community 4`, `Community 7`, `Community 11`?**
  _High betweenness centrality (0.230) - this node is a cross-community bridge._
- **Why does `SettingsManagerTests` connect `Community 2` to `Community 8`, `Community 7`?**
  _High betweenness centrality (0.193) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ViewController` (e.g. with `.setUp()` and `.testInitialBackgroundColorBasedOnAppearance()`) actually correct?**
  _`ViewController` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `dateModified`, `dateCreated`, `dateAdded` to the rest of the system?**
  _23 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._