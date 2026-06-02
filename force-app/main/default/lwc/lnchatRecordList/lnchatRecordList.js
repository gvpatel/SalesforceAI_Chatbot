import { LightningElement, api, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import searchRecords from "@salesforce/apex/LNChatController.searchRecords";

export default class LnchatRecordList extends NavigationMixin(
  LightningElement
) {
  @api cardData = {};

  @track isLoading = true;
  @track hasError = false;
  @track errorMessage = "";
  @track tableRows = [];
  @track tableColumns = [];
  @track totalCount = 0;

  connectedCallback() {
    this.executeSearch();
  }

  async executeSearch() {
    this.isLoading = true;
    this.hasError = false;

    const d = this.cardData || {};
    try {
      const result = await searchRecords({
        objectApiName: d.objectApiName || "Account",
        filtersJson: d.filters ? JSON.stringify(d.filters) : "[]",
        columnsJson: d.columns ? JSON.stringify(d.columns) : "[]",
        orderByField: d.orderBy || null,
        orderDesc: d.orderDesc || false,
        limitRows: d.limitRows || 20
      });

      this.totalCount = result.count || 0;
      this._rawColumns = (result.columns || []).filter((c) => c !== "Id");
      this.tableRows = this.buildRows(result.rows || [], result.columns || []);
      this.tableColumns = this.buildColumns(
        result.columns || [],
        result.objectApiName
      );
    } catch (e) {
      this.hasError = true;
      this.errorMessage =
        e && e.body && e.body.message ? e.body.message : "Search failed.";
    } finally {
      this.isLoading = false;
    }
  }

  // eslint-disable-next-line no-unused-vars
  buildColumns(columns, objectApiName) {
    const cols = columns
      .filter((c) => c !== "Id")
      .map((c) => ({
        label: this.formatLabel(c),
        fieldName: c.includes(".") ? c.replace(".", "_") : c,
        type: "text",
        cellAttributes: { alignment: "left" }
      }));

    // First column links to the record
    if (cols.length > 0) {
      cols[0] = {
        label: cols[0].label,
        fieldName: "recordUrl",
        type: "url",
        typeAttributes: {
          label: { fieldName: cols[0].fieldName },
          target: "_self"
        }
      };
    }

    return cols;
  }

  buildRows(rows, columns) {
    return rows.map((row) => {
      const flat = {};
      columns.forEach((col) => {
        if (col.includes(".")) {
          const [parent, child] = col.split(".");
          const parentObj = row[parent];
          flat[col.replace(".", "_")] = parentObj ? parentObj[child] : "";
        } else {
          flat[col] = row[col] != null ? String(row[col]) : "";
        }
      });
      flat.Id = row.Id || "";
      flat.recordUrl = row.Id ? `/lightning/r/${row.Id}/view` : "";
      return flat;
    });
  }

  formatLabel(fieldName) {
    return fieldName
      .replace(/__c$/i, "")
      .replace(/__r$/i, "")
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/_/g, " ");
  }

  handleRowAction(event) {
    const row = event.detail.row;
    if (!row || !row.Id) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: row.Id, actionName: "view" }
    });
  }

  get hasRows() {
    return this.tableRows && this.tableRows.length > 0;
  }

  get resultCountLabel() {
    if (this.totalCount === 0) return "No records found";
    return this.totalCount === 1
      ? "1 record found"
      : `${this.totalCount} records found`;
  }

  handleExport() {
    const cols = this._rawColumns || [];
    const headers = cols.map((c) => this.formatLabel(c));
    const rows = this.tableRows.map((row) =>
      cols.map((col) => {
        const key = col.includes(".") ? col.replace(".", "_") : col;
        return this.escapeCsvValue(row[key] || "");
      })
    );
    const csv = [headers.join(","), ...rows.map((r) => r.join(","))].join("\n");
    const date = new Date().toISOString().split("T")[0];
    const filename = `${(this.cardData && this.cardData.objectApiName) || "export"}_${date}.csv`;
    const encodedUri = "data:text/csv;charset=utf-8," + encodeURIComponent(csv);
    const a = document.createElement("a");
    a.setAttribute("href", encodedUri);
    a.setAttribute("download", filename);
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  }

  escapeCsvValue(val) {
    const str = String(val);
    if (str.includes(",") || str.includes('"') || str.includes("\n")) {
      return '"' + str.replace(/"/g, '""') + '"';
    }
    return str;
  }
}
