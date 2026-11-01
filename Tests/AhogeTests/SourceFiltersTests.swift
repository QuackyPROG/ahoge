import XCTest
@testable import Ahoge

final class SourceFiltersTests: XCTestCase {
    private let listJSON = """
    [
      {"type":"header","name":"Basics"},
      {"type":"separator"},
      {"type":"text","key":"author","name":"Author"},
      {"type":"checkbox","key":"chapters","name":"Has chapters","default":true},
      {"type":"tristate","key":"color","name":"Full color"},
      {"type":"select","key":"mode","name":"Mode","options":[{"value":"and","label":"AND"},{"value":"or","label":"OR"}],"default":"or"},
      {"type":"sort","key":"sort","name":"Sort","options":[{"value":"follows","label":"Follows"},{"value":"title","label":"Title"}]},
      {"type":"slider","key":"future","name":"From a newer contract"},
      {"type":"group","key":"tags","name":"Tags","filters":[
        {"type":"tristate","key":"action","name":"Action"},
        {"type":"tristate","key":"drama","name":"Drama"}
      ]}
    ]
    """

    private func decode() throws -> [SourceFilter] {
        try JSONDecoder().decode(FilterList.self, from: Data(listJSON.utf8)).filters
    }

    private func object(_ json: String) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    func testDecodesEveryTypeAndSkipsUnknown() throws {
        let filters = try decode()
        XCTAssertEqual(filters.count, 8)
        XCTAssertEqual(filters[0], .header(name: "Basics"))
        XCTAssertEqual(filters[1], .separator)
        XCTAssertEqual(filters[3], .checkbox(key: "chapters", name: "Has chapters", defaultValue: true))
        XCTAssertEqual(filters[5].defaultValue, .option("or"))
        XCTAssertEqual(filters[6].defaultValue, .sort(SortValue(value: "follows", ascending: false)))
        XCTAssertEqual(filters[7].key, "tags")
    }

    func testDefaultsActiveCountAndJSON() throws {
        var state = FilterState(filters: try decode())
        XCTAssertEqual(state.activeCount, 0)
        XCTAssertEqual(try object(state.json()), try object("""
        {"author":"","chapters":true,"color":0,"mode":"or","sort":{"value":"follows","ascending":false},"tags":{"action":0,"drama":0}}
        """))

        state.values["author"] = .text("Oda")
        state.values["tags"] = .group(["action": .state(.include), "drama": .state(.exclude)])
        XCTAssertEqual(state.activeCount, 3)

        state.reset()
        XCTAssertEqual(state.activeCount, 0)
    }

    func testIncludeNamedFindsNestedFilter() throws {
        var state = FilterState(filters: try decode())
        XCTAssertTrue(state.include(named: "drama"))
        XCTAssertEqual(state.values["tags"], .group(["action": .state(.ignore), "drama": .state(.include)]))
        XCTAssertFalse(state.include(named: "Romance"))
        XCTAssertEqual(state.activeCount, 1)
    }

    func testTriStateCycles() {
        XCTAssertEqual(TriState.ignore.next, .include)
        XCTAssertEqual(TriState.include.next, .exclude)
        XCTAssertEqual(TriState.exclude.next, .ignore)
    }

    func testScriptReceivesFilterValuesAsObject() async throws {
        let source = try ScriptSource(script: """
        var source = {
          filters: async function () {
            return [{ type: "checkbox", key: "done", name: "Completed" }, { type: "group", key: "g", name: "G", filters: [{ type: "tristate", key: "a", name: "A" }] }];
          },
          search: async function (q, page, f) {
            var label = q + "|" + page + "|" + typeof f.done + ":" + f.done + "|" + f.g.a;
            return { manga: [{ url: "/x", title: label, cover: "" }], hasNextPage: false };
          }
        };
        """)
        var state = FilterState(filters: try await source.filters())
        XCTAssertEqual(state.filters.count, 2)
        XCTAssertTrue(state.include(named: "A"))
        state.values["done"] = .bool(true)
        let page = try await source.search(query: "q", page: 2, filters: state)
        XCTAssertEqual(page.manga.first?.title, "q|2|boolean:true|1")
    }

    func testSourceWithoutFiltersHasNone() async throws {
        let source = try ScriptSource(script: "var source = { search: async function (q, p, f) { return { manga: [], hasNextPage: f !== undefined }; } };")
        let filters = try await source.filters()
        XCTAssertTrue(filters.isEmpty)
        let page = try await source.search(query: "x", page: 1, filters: FilterState(filters: filters))
        XCTAssertFalse(page.hasNextPage)
    }
}
