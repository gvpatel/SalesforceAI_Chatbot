import { LightningElement, api } from 'lwc';

const BADGE_CLS = {
    success: 'rs-badge rs-badge-success',
    warning: 'rs-badge rs-badge-warning',
    error:   'rs-badge rs-badge-error',
    brand:   'rs-badge rs-badge-brand',
    neutral: 'rs-badge rs-badge-neutral'
};

const HEADER_BADGE_CLS = {
    success: 'rs-status rs-status-success',
    warning: 'rs-status rs-status-warning',
    error:   'rs-status rs-status-error',
    brand:   'rs-status rs-status-brand',
    neutral: 'rs-status rs-status-neutral'
};

let _keyCounter = 0;

export default class LnchatRecordSummary extends LightningElement {
    @api summaryData = {};

    get header() {
        return (this.summaryData && this.summaryData.header) || {};
    }

    get headerName()     { return this.header.name     || ''; }
    get headerSubtitle() { return this.header.subtitle || ''; }
    get headerBadge()    { return this.header.badge    || ''; }

    get headerBadgeClass() {
        const c = this.header.badgeColor || 'success';
        return HEADER_BADGE_CLS[c] || HEADER_BADGE_CLS.neutral;
    }

    get hasKpis() {
        return Array.isArray(this.summaryData && this.summaryData.kpis) && this.summaryData.kpis.length > 0;
    }

    get kpis() {
        return (this.summaryData && this.summaryData.kpis) || [];
    }

    get sections() {
        const raw = (this.summaryData && this.summaryData.sections) || [];
        return raw
            .map((sec) => {
                const NA = 'N/A';
                const clean = (v) => (v && v !== NA ? v : '');
                const items = (sec.items || []).map((item) => ({
                    key:      ++_keyCounter + '-' + (item.name || ''),
                    recordId: item.recordId || '',
                    name:     item.name   || '',
                    subtitle: clean(item.subtitle),
                    date:     clean(item.date),
                    amount:   clean(item.amount),
                    hasLink:  !!(item.recordId),
                    badgeList: (item.badges || []).map((b) => ({
                        label: b.label || b,
                        cls: BADGE_CLS[b.color || b] || BADGE_CLS.neutral
                    }))
                }));
                return {
                    title:    sec.title || '',
                    hasItems: items.length > 0,
                    items
                };
            })
            .filter((sec) => sec.hasItems);
    }

    handleRecordClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) return;

        this.dispatchEvent(new CustomEvent('recordnavigate', {
            detail: { recordId },
            bubbles: true,
            composed: true
        }));
    }
}
