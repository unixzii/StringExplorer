//
//  StringExplorer.swift
//  StringExplorer
//
//  Created by Cyandev on 2024/2/23.
//

import SwiftUI
import Observation

@Observable
class ViewContext {
    
    var showsUnicodeScalar = true
    var showsUTF16CodeUnit = true
    var showsUTF8CodeUnit = true
    
    var hexMode = true
    
    var highlightedGroupID: Int?
    
    init() { }
}

fileprivate struct AppView: View {
    
    private enum Field: Hashable {
        case input
        case hexMode
    }
    
    @State private var input: String = ""
    @State private var viewContext = ViewContext()
    @FocusState private var focusedField: Field?
    
    var body: some View {
        VStack(spacing: 0) {
            VStack {
                TextField("Input", text: $input)
                    .focused($focusedField, equals: .input)
                
                HStack {
                    FilterToggle(title: "Unicode Scalar", keyPath: \.showsUnicodeScalar)
                    FilterToggle(title: "UTF-16", keyPath: \.showsUTF16CodeUnit)
                        .foregroundStyle(Color(nsColor: .systemOrange))
                    FilterToggle(title: "UTF-8", keyPath: \.showsUTF8CodeUnit)
                        .foregroundStyle(Color(nsColor: .systemBlue))
                    
                    Spacer()
                    
                    Toggle("Hex", isOn: .init(get: {
                        return viewContext.hexMode
                    }, set: { newValue in
                        viewContext.hexMode = newValue
                    }))
                    .toggleStyle(SwitchToggleStyle())
                    .controlSize(.mini)
                    .bold()
                    .focused($focusedField, equals: .hexMode)
                    .help("Show values in hexadecimal")
                }
            }
            .padding()
            
            Divider()
            
            CharacterCellProvider(string: input) { cells in
                CharacterCellGridView(cells: cells)
            }
            .equatable()
        }
        .environment(viewContext)
        .onAppear {
            focusedField = .input
        }
    }
}

fileprivate struct FilterToggle: View {
    
    let title: String
    let keyPath: WritableKeyPath<ViewContext, Bool>
    
    @Environment(ViewContext.self) private var viewContext
    
    private var checkedFilters: Int {
        let filterValues = [
            viewContext.showsUnicodeScalar,
            viewContext.showsUTF16CodeUnit,
            viewContext.showsUTF8CodeUnit
        ]
        return filterValues.filter(Bool.init(_:)).count
    }
    
    var body: some View {
        Toggle(title, isOn: .init(get: {
            return viewContext[keyPath: keyPath]
        }, set: { newValue in
            var viewContext = self.viewContext
            viewContext[keyPath: keyPath] = newValue
        }))
        .font(.system(size: 12, weight: .bold).monospaced())
        .disabled(checkedFilters <= 1 && viewContext[keyPath: keyPath])
    }
}

fileprivate struct CharacterCell: Hashable {
    
    struct IndexedValue<T: Hashable>: Hashable {
        
        let index: Int
        let value: T
    }
    
    let groupID: Int
    
    let character: IndexedValue<Character>?
    let unicodeScalar: IndexedValue<UnicodeScalar>?
    let utf16CodeUnit: IndexedValue<UInt16>?
    let utf8CodeUnit: IndexedValue<UInt8>?
}

extension CharacterCell: Identifiable {
    
    var id: Int {
        return hashValue
    }
}

fileprivate struct WalkState<V: BidirectionalCollection> {
    
    let view: V
    private var index: V.Index
    private(set) var onHold = false
    private var holdAfterSteps: Int? = nil
    
    init(_ view: V) {
        self.view = view
        index = view.startIndex
    }
    
    mutating func next() -> V.Element? {
        guard !onHold && index != view.endIndex else {
            return nil
        }
        
        defer {
            index = view.index(after: index)
        }
        
        if let holdAfterSteps {
            self.holdAfterSteps = holdAfterSteps - 1
            onHold = holdAfterSteps == 1
        }
        
        return view[index]
    }
    
    mutating func hold() {
        onHold = true
        holdAfterSteps = nil
    }
    
    mutating func hold(after steps: Int) {
        holdAfterSteps = steps
    }
    
    mutating func resume() {
        onHold = false
        holdAfterSteps = nil
    }
}

fileprivate struct CharacterCellProvider<Content>: View, Equatable where Content: View {
    
    let string: String
    let content: ([CharacterCell]) -> Content
    
    static func == (lhs: CharacterCellProvider<Content>, rhs: CharacterCellProvider<Content>) -> Bool {
        lhs.string == rhs.string
    }
    
    init(string: String, @ViewBuilder content: @escaping ([CharacterCell]) -> Content) {
        self.string = string
        self.content = content
    }
    
    var body: Content {
        var cells = [CharacterCell]()
        
        var characterRawIndex = 0
        var unicodeScalarRawIndex = 0
        var utf16RawIndex = 0
        var utf8RawIndex = 0
        
        for character in string {
            var unicodeWalkState = WalkState(character.unicodeScalars)
            var utf16WalkState = WalkState(character.utf16)
            var utf8WalkState = WalkState(character.utf8)
            
            var firstCellOfCharacter = true
            while true {
                var unicodeScalar: CharacterCell.IndexedValue<UnicodeScalar>? = nil
                if let value = unicodeWalkState.next() {
                    unicodeScalar = .init(index: unicodeScalarRawIndex, value: value)
                    unicodeScalarRawIndex += 1
                    unicodeWalkState.hold()
                }
                
                var utf16CodeUnit: CharacterCell.IndexedValue<UInt16>? = nil
                if let value = utf16WalkState.next() {
                    utf16CodeUnit = .init(index: utf16RawIndex, value: value)
                    utf16RawIndex += 1
                    if (value >> 10) != 0x36 {
                        utf16WalkState.hold()
                    }
                }
                
                var utf8CodeUnit: CharacterCell.IndexedValue<UInt8>? = nil
                if let value = utf8WalkState.next() {
                    utf8CodeUnit = .init(index: utf8RawIndex, value: value)
                    utf8RawIndex += 1
                    if value & 0xc0 == 0x80 {
                        // Don't update walking state at the continuation byte.
                    } else if value & 0x80 == 0 {
                        utf8WalkState.hold()
                    } else if value & 0xe0 == 0xc0 {
                        utf8WalkState.hold(after: 1)
                    } else if value & 0xf0 == 0xe0 {
                        utf8WalkState.hold(after: 2)
                    } else {
                       utf8WalkState.hold(after: 3)
                   }
                }
                
                // UTF8 sequence should always be the longest one, resume walking
                // all the sequences when we meet the Unicode scalar boundary.
                if utf8WalkState.onHold {
                    unicodeWalkState.resume()
                    utf16WalkState.resume()
                    utf8WalkState.resume()
                }
                
                if unicodeScalar == nil && utf16CodeUnit == nil && utf8CodeUnit == nil {
                    break
                }
                
                let characterValue: CharacterCell.IndexedValue<Character>? = if firstCellOfCharacter {
                    .init(index: characterRawIndex, value: character)
                } else {
                    nil
                }
                
                let cell = CharacterCell(
                    groupID: characterRawIndex,
                    character: characterValue,
                    unicodeScalar: unicodeScalar,
                    utf16CodeUnit: utf16CodeUnit,
                    utf8CodeUnit: utf8CodeUnit
                )
                cells.append(cell)
                
                firstCellOfCharacter = false
            }
            
            characterRawIndex += 1
        }
        
        return content(cells)
    }
}

fileprivate struct CharacterCellGridView: View {
    
    let cells: [CharacterCell]
    
    @State private var gridColumns = [GridItem]()
    @State private var filteredCells = [CharacterCell]()
    @Environment(ViewContext.self) private var viewContext
    
    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 4) {
                ForEach(filteredCells) { cell in
                    RubyView(cell: cell)
                }
            }
            .padding(4)
        }
        .frame(minWidth: 400)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size) { _, newValue in
                        updateGridColumns(with: newValue)
                    }
                    .onAppear {
                        updateGridColumns(with: geometry.size)
                    }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: [
            viewContext.showsUnicodeScalar,
            viewContext.showsUTF16CodeUnit,
            viewContext.showsUTF8CodeUnit
        ]) { _, _ in
            reloadFilter()
        }
        .onChange(of: cells, { _, _ in
            reloadFilter()
        })
        .onAppear {
            reloadFilter()
        }
    }
    
    func updateGridColumns(with size: CGSize) {
        let gridWidth: CGFloat = 80
        let spacing: CGFloat = 4
        let numberOfColumns = Int(floor((size.width - 8) / (gridWidth + spacing)))
        let templateItem = GridItem(.fixed(gridWidth), spacing: spacing)
        gridColumns = .init(repeating: templateItem, count: numberOfColumns)
    }
    
    func reloadFilter() {
        filteredCells = cells.filter { cell in
            let unicodeScalarVisible = cell.unicodeScalar != nil && viewContext.showsUnicodeScalar
            let utf16CodeUnitVisible = cell.utf16CodeUnit != nil && viewContext.showsUTF16CodeUnit
            let utf8CodeUnitVisible = cell.utf8CodeUnit != nil && viewContext.showsUTF8CodeUnit
            return unicodeScalarVisible || utf16CodeUnitVisible || utf8CodeUnitVisible
        }
    }
}

fileprivate struct RubyView: View {
    
    @Environment(ViewContext.self) private var viewContext
    
    let cell: CharacterCell
    
    var isHighlighted: Bool {
        return viewContext.highlightedGroupID == cell.groupID
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let character = cell.character {
                makeText(String(character.value), index: character.index)
            } else {
                makeText(" ", index: nil)
            }
            
            if viewContext.showsUnicodeScalar {
                makeDivider()
                if let unicodeScalar = cell.unicodeScalar {
                    makeText(String(unicodeScalar.value), index: unicodeScalar.index)
                } else {
                    makeText(" ", index: nil)
                }
            }
            
            if viewContext.showsUTF16CodeUnit {
                makeDivider()
                if let utf16CodeUnit = cell.utf16CodeUnit {
                    makeText(formatCodeUnit(utf16CodeUnit.value, hexMinimumLength: 4),
                             index: utf16CodeUnit.index,
                             monospaced: true,
                             color: .systemOrange)
                } else {
                    makeText(" ", index: nil)
                }
            }
            
            if viewContext.showsUTF8CodeUnit {
                makeDivider()
                if let utf8CodeUnit = cell.utf8CodeUnit {
                    makeText(formatCodeUnit(utf8CodeUnit.value, hexMinimumLength: 2),
                             index: utf8CodeUnit.index,
                             monospaced: true,
                             color: .systemBlue)
                } else {
                    makeText(" ", index: nil)
                }
            }
        }
        .padding(6)
        .background {
            Color(nsColor: .textColor)
                .opacity(isHighlighted ? 0.08 : 0.05)
                .animation(.linear(duration: 0.1), value: isHighlighted)
            
        }
        .clipShape(RoundedRectangle(cornerSize: .init(width: 6, height: 6)))
        .onHover { hovering in
            if hovering {
                viewContext.highlightedGroupID = cell.groupID
            } else {
                viewContext.highlightedGroupID = nil
            }
        }
    }
    
    private func makeDivider() -> some View {
        return Color(nsColor: .separatorColor)
            .frame(height: 1)
            .padding(.vertical, 1)
    }
    
    private func makeText(_ text: String,
                          index: Int?,
                          monospaced: Bool = false,
                          color: NSColor? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(index.map(String.init) ?? " ")
                .font(.system(size: 10).monospaced())
                .opacity(0.5)
            Text(text)
                .foregroundStyle(Color(nsColor: color ?? .textColor))
                .font(monospaced ? .system(size: 12).monospaced() : .system(size: 12))
        }
        .padding(.init(top: 2, leading: 4, bottom: 2, trailing: 4))
    }
    
    private func formatCodeUnit<T: BinaryInteger>(_ value: T,
                                                  hexMinimumLength: Int) -> String {
        if viewContext.hexMode {
            return value.hexString(minimumLength: hexMinimumLength)
        } else {
            return String(value)
        }
    }
}

fileprivate extension BinaryInteger {
    
    func hexString(minimumLength: Int) -> String {
        var string = String(self, radix: 16)
        if string.count < minimumLength {
            let padding = minimumLength - string.count
            string = String(repeating: "0", count: padding) + string
        }
        return "0x\(string)"
    }
}

@main
struct App: SwiftUI.App {
    
    var body: some Scene {
        WindowGroup {
            AppView()
        }
    }
}
