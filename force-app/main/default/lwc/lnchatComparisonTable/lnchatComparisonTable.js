import { LightningElement, api, track } from "lwc";

export default class LnchatComparisonTable extends LightningElement {
  @track _columns = [];
  @track _rows = [];
  @track sortKey = "";
  @track sortAsc = true;
  @api highlightDiffs = false;

  @api
  set tableData(data) {
    if (!data) return;
    // eslint-disable-next-line @lwc/lwc/no-api-reassignments
    this.highlightDiffs = data.highlightDiffs !== false;

    const rawCols = data.columns || ["Field", "Salesforce", "External System"];
    this._columns = [
      {
        key: "field",
        label: rawCols[0] || "Field",
        headerClass: "th-field",
        isSorted: false,
        sortIcon: ""
      },
      {
        key: "salesforceValue",
        label: rawCols[1] || "Salesforce",
        headerClass: "th-sf",
        isSorted: false,
        sortIcon: ""
      },
      {
        key: "externalValue",
        label: rawCols[2] || "External System",
        headerClass: "th-ext",
        isSorted: false,
        sortIcon: ""
      }
    ];

    this._rows = (data.rows || []).map((row) => ({
      field: row.field || "",
      salesforceValue: String(
        row.salesforceValue !== undefined && row.salesforceValue !== null
          ? row.salesforceValue
          : "N/A"
      ),
      externalValue: String(
        row.externalValue !== undefined && row.externalValue !== null
          ? row.externalValue
          : "N/A"
      ),
      isDifferent: !!row.isDifferent,
      rowClass: this.getRowClass(row)
    }));
  }

  get tableData() {
    return {
      columns: this._columns,
      rows: this._rows,
      highlightDiffs: this.highlightDiffs
    };
  }

  get columns() {
    return this._columns.map((col) => ({
      ...col,
      isSorted: col.key === this.sortKey,
      sortIcon:
        this.sortKey === col.key
          ? this.sortAsc
            ? "utility:arrowup"
            : "utility:arrowdown"
          : ""
    }));
  }

  get sortedRows() {
    if (!this.sortKey) return this._rows;

    const key = this.sortKey;
    const asc = this.sortAsc;
    return [...this._rows].sort((a, b) => {
      const va = (a[key] || "").toLowerCase();
      const vb = (b[key] || "").toLowerCase();
      if (va < vb) return asc ? -1 : 1;
      if (va > vb) return asc ? 1 : -1;
      return 0;
    });
  }

  get diffCount() {
    return this._rows.filter((r) => r.isDifferent).length;
  }

  get hasDiffs() {
    return this.diffCount > 0;
  }

  handleSort(event) {
    const key = event.currentTarget.dataset.key;
    if (this.sortKey === key) {
      this.sortAsc = !this.sortAsc;
    } else {
      this.sortKey = key;
      this.sortAsc = true;
    }
  }

  getRowClass(row) {
    let cls = "comparison-row";
    if (this.highlightDiffs && row.isDifferent) {
      cls += " row-diff";
    }
    return cls;
  }
}
