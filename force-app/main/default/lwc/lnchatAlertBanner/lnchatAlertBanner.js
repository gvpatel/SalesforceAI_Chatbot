import { LightningElement, api, track } from 'lwc';

export default class LnchatAlertBanner extends LightningElement {
    @api severity = 'info';
    @api alertTitle = '';
    @api message = '';
    @api details = [];
    @api allowBypass = false;

    @track isExpanded = false;
    @track isDismissed = false;
    @track bypassDone = false;

    get bannerClass() {
        const severityMap = {
            critical: 'alert-banner alert-critical',
            warning: 'alert-banner alert-warning',
            info: 'alert-banner alert-info',
            success: 'alert-banner alert-success'
        };
        return severityMap[this.severity] || 'alert-banner alert-info';
    }

    get severityIcon() {
        const iconMap = {
            critical: 'utility:error',
            warning: 'utility:warning',
            info: 'utility:info',
            success: 'utility:success'
        };
        return iconMap[this.severity] || 'utility:info';
    }

    get expandIcon() {
        return this.isExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get hasDetails() {
        return this.details && this.details.length > 0;
    }

    toggleExpanded() {
        if (this.hasDetails) {
            this.isExpanded = !this.isExpanded;
        }
    }

    handleDismiss(event) {
        event.stopPropagation();
        this.isDismissed = true;
        this.dispatchEvent(new CustomEvent('dismiss'));
    }

    handleProceed(event) {
        event.stopPropagation();
        this.bypassDone = true;
        this.dispatchEvent(new CustomEvent('alertproceed', {
            bubbles: true,
            composed: true
        }));
    }

    handleBypassCancel(event) {
        event.stopPropagation();
        this.bypassDone = true;
        this.dispatchEvent(new CustomEvent('alertcancel', {
            bubbles: true,
            composed: true
        }));
    }
}
