import Testing

@testable import CarrierCore

/// Twelve cells are four full columns; eleven leave the last column with two cells; ten leave it with one.
@Suite struct ThemeGalleryMoveTests {
    private func move(_ index: Int, _ key: ThemeGalleryKey, count: Int = 12) -> Int { themeGalleryMove(from: index, key: key, count: count) }

    @Test func up_and_down_move_one_cell_inside_a_column() {
        #expect(move(1, .down) == 2)
        #expect(move(1, .up) == 0)
        #expect(move(3, .down) == 4)
        #expect(move(4, .up) == 3)
    }

    @Test func up_from_the_top_and_down_from_the_bottom_of_a_column_stay_put() {
        #expect(move(0, .up) == 0)
        #expect(move(3, .up) == 3)
        #expect(move(2, .down) == 2)
        #expect(move(5, .down) == 5)
    }

    @Test func left_and_right_move_one_column_in_the_same_row() {
        #expect(move(1, .right) == 4)
        #expect(move(4, .left) == 1)
        #expect(move(8, .right) == 11)
        #expect(move(11, .left) == 8)
    }

    @Test func left_from_the_first_column_and_right_from_the_last_stay_put() {
        #expect(move(2, .left) == 2)
        #expect(move(11, .right) == 11)
        #expect(move(9, .right) == 9)
    }

    @Test func down_from_the_last_cell_stays_when_the_last_column_is_short() {
        #expect(move(10, .down, count: 11) == 10)
        #expect(move(9, .down, count: 11) == 10)
        #expect(move(9, .down, count: 10) == 9)
    }

    @Test func right_into_a_shorter_last_column_goes_to_its_last_cell() {
        // eleven cells: the last column holds 9 and 10, row two has no cell there
        #expect(move(8, .right, count: 11) == 10)
        #expect(move(7, .right, count: 11) == 10)
        #expect(move(6, .right, count: 11) == 9)
        // ten cells: the last column holds only 9
        #expect(move(8, .right, count: 10) == 9)
        #expect(move(7, .right, count: 10) == 9)
        #expect(move(6, .right, count: 10) == 9)
        // one column earlier the cell is still the same row
        #expect(move(5, .right, count: 10) == 8)
    }

    @Test func the_last_column_ends_the_row_even_when_short() {
        #expect(move(10, .right, count: 11) == 10)
        #expect(move(9, .right, count: 10) == 9)
    }

    @Test func one_cell_and_no_cells_do_not_move() {
        for key in [ThemeGalleryKey.up, .down, .left, .right] {
            #expect(move(0, key, count: 1) == 0)
            #expect(move(0, key, count: 0) == 0)
        }
    }

    @Test func a_cell_out_of_range_stays_where_it_is() {
        #expect(move(40, .left) == 40)
        #expect(move(-1, .right) == -1)
    }
}
