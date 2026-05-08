import { LightningElement, api, track } from 'lwc';

export default class LnchatTableView extends LightningElement {
    @track _columns = [];
    @track _rows = [];
    @track sortColIndex = null;
    @track sortAsc = true;

    @api
    set tableData(data) {
        if (!data) return;
        this._columns = (data.columns || []).map(String);
        this._rows = (data.rows || []).map((row) =>
            Array.isArray(row) ? row.map((v) => String(v != null ? v : '')) : []
        );
    }

    get tableData() {
        return { columns: this._columns, rows: this._rows };
    }

    get columns() {
        return this._columns.map((label, index) => ({
            index,
            label,
            isSorted: index === this.sortColIndex,
            sortIcon:
                index === this.sortColIndex
                    ? this.sortAsc
                        ? 'utility:arrowup'
                        : 'utility:arrowdown'
                    : ''
        }));
    }

    get sortedRows() {
        const mapped = this._rows.map((cells, ri) => ({
            key: 'r' + ri,
            rowClass: ri % 2 === 0 ? 'data-row' : 'data-row row-alt',
            cells: cells.map((value, ci) => ({
                index: ci,
                value,
                cellClass: ci === 0 ? 'cell cell-first' : 'cell'
            }))
        }));

        if (this.sortColIndex === null) return mapped;

        const idx = this.sortColIndex;
        const asc = this.sortAsc;
        return [...mapped].sort((a, b) => {
            const va = (a.cells[idx] ? a.cells[idx].value : '').toLowerCase();
            const vb = (b.cells[idx] ? b.cells[idx].value : '').toLowerCase();
            if (va < vb) return asc ? -1 : 1;
            if (va > vb) return asc ? 1 : -1;
            return 0;
        });
    }

    get isEmpty() {
        return this._rows.length === 0;
    }

    get rowCount() {
        return this._rows.length;
    }

    handleSort(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (this.sortColIndex === idx) {
            this.sortAsc = !this.sortAsc;
        } else {
            this.sortColIndex = idx;
            this.sortAsc = true;
        }
    }
}
