import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const BADGE_CLASS_MAP = {
    success: 'badge badge-success',
    warning: 'badge badge-warning',
    error: 'badge badge-error',
    brand: 'badge badge-brand'
};

export default class LnchatResponseRenderer extends NavigationMixin(LightningElement) {
    @api responseType = 'summary';
    @api title = '';
    @api summary = '';
    @api data = {};
    @api recordId = '';
    @api objectApiName = '';

    @track _actions = [];

    @api
    set actions(value) {
        this._actions = (value || []).map((a) => ({
            ...a,
            inputVariablesJson: JSON.stringify(a.inputVariables || {})
        }));
    }

    get actions() {
        return this._actions;
    }

    // ─── Type guards ─────────────────────────────────────────────────────────

    get isKpiCards()      { return this.responseType === 'kpi_cards'; }
    get isChart()         { return this.responseType === 'chart'; }
    get isComparison()    { return this.responseType === 'comparison'; }
    get isTimeline()      { return this.responseType === 'timeline'; }
    get isAlert()         { return this.responseType === 'alert'; }
    get isTable()         { return this.responseType === 'table'; }
    get isRecordSummary() { return this.responseType === 'record_summary'; }
    get showTimeline() { return this.isRecordSummary && this.objectApiName === 'Account' && !!this.recordId; }
    get isRecordAction()  { return this.responseType === 'record_action'; }
    get isRecordList()    { return this.responseType === 'record_list'; }
    get isSummary() {
        return (this.responseType === 'summary' || !this.responseType)
            && !this.isRecordAction && !this.isRecordSummary && !this.isTable && !this.isRecordList;
    }

    get hasSummary() { return !!this.summary; }
    get hasTitle() { return !!this.title && !this.isSummary && !this.isChart; }
    get hasActions() { return this._actions && this._actions.length > 0; }

    // ─── KPI Cards ───────────────────────────────────────────────────────────

    get kpiCards() {
        return (this.data && this.data.cards) ? this.data.cards : [];
    }

    // ─── Chart ───────────────────────────────────────────────────────────────

    get chartType() { return (this.data && this.data.chartType) || 'bar'; }
    get chartTitle() { return this.title; }
    get chartLabels() { return (this.data && this.data.labels) || []; }
    get chartDatasets() { return (this.data && this.data.datasets) || []; }

    // ─── Comparison ──────────────────────────────────────────────────────────

    get comparisonData() { return this.data || {}; }

    // ─── Table ───────────────────────────────────────────────────────────────

    get tableViewData() { return this.data || {}; }

    // ─── Record List ─────────────────────────────────────────────────────────

    get recordListData() { return this.data || {}; }

    // ─── Timeline ────────────────────────────────────────────────────────────

    get timelineEvents() {
        return (this.data && this.data.events) ? this.data.events : [];
    }

    // ─── Alert ───────────────────────────────────────────────────────────────

    get alertSeverity()    { return (this.data && this.data.severity)    || 'info'; }
    get alertTitle()       { return (this.data && this.data.alertTitle)  || this.title; }
    get alertMessage()     { return (this.data && this.data.message)     || ''; }
    get alertDetails()     { return (this.data && this.data.details)     || []; }
    get alertAllowBypass() { return !!(this.data && this.data.allowBypass); }

    // ─── Summary ─────────────────────────────────────────────────────────────

    get summarySections() {
        return (this.data && this.data.sections) ? this.data.sections : [];
    }

    get summaryBadges() {
        const badges = (this.data && this.data.badges) ? this.data.badges : [];
        return badges.map((b) => ({
            label: b.label,
            badgeClass: BADGE_CLASS_MAP[b.color] || BADGE_CLASS_MAP.brand
        }));
    }

    get hasBadges() { return this.summaryBadges.length > 0; }

    // ─── Record Summary ──────────────────────────────────────────────────────

    get recordSummaryData() { return this.data || {}; }

    // ─── Record Action ───────────────────────────────────────────────────────

    get recordActionOperation() { return (this.data && this.data.operation) || 'create'; }
    get recordActionObject() { return (this.data && this.data.objectApiName) || ''; }
    get recordActionRecordId() { return (this.data && this.data.recordId) || ''; }
    get recordActionFields() { return (this.data && this.data.fields) || {}; }

    // ─── Action handler ──────────────────────────────────────────────────────

    handleAction(event) {
        const flowApiName = event.currentTarget.dataset.flow;
        const inputVariablesJson = event.currentTarget.dataset.vars;

        if (!flowApiName) return;

        let inputVariables = {};
        try {
            inputVariables = JSON.parse(inputVariablesJson || '{}');
        } catch (e) {
            inputVariables = {};
        }

        if (this.recordId) {
            inputVariables.recordId = this.recordId;
        }

        const inputVarsList = Object.entries(inputVariables).map(([name, value]) => ({
            name,
            type: typeof value === 'string' ? 'String' : 'Number',
            value
        }));

        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__flowRunner'
            },
            state: {
                c__flowApiName: flowApiName,
                c__inputVariables: JSON.stringify(inputVarsList)
            }
        });

        this.dispatchEvent(new CustomEvent('actionlaunched', {
            detail: { flowApiName, inputVariables },
            bubbles: true,
            composed: true
        }));
    }
}
