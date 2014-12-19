var React = require('react');
var moment = require('moment');

var WebUtilsMixin       = require('../../mixins/webUtilsMixin.coffee');
var Spacer              = require('react-redhat/Spacer');

var GeoComponent        = require('./geo.jsx');
var TimezoneComponent   = require('./timezone.jsx');
var RoleComponent       = require('./role.jsx');
var OverlayTrigger      = require('react-bootstrap/OverlayTrigger');
var Popover             = require('react-bootstrap/Popover');
var Button              = require('react-bootstrap/Button');
var SplitButton         = require('react-bootstrap/SplitButton');
var DropdownButton      = require('react-bootstrap/DropdownButton');
var MenuItem            = require('react-bootstrap/MenuItem');
var Label               = require('react-bootstrap/Label');

module.exports = React.createClass({
    displayName: 'User',
    mixins: [WebUtilsMixin],
    render: function() {
        var geoStyle, popover, style, title, user, roles, skillMatrixMenuItem, engineerReportMenuItem ;
        if (!this.isDefined(this.props.resource, 'resource')) {
            return null;
        } else {
            user = this.props.resource.resource;
        }

        if (user.email == null) {
            return <span>{user.fullName}</span>
        } else {
            roles = _.map(user.roles, (role) => <RoleComponent role={role}></RoleComponent>);
            popover = (
                <Popover title={user.fullName}>
                    <div>{user.title}</div>
                    <GeoComponent geo={user.superRegion}></GeoComponent>
                    &nbsp;
                    <TimezoneComponent timezone={user.timezone}></TimezoneComponent>
                    &nbsp;
                    <Spacer />
                    {roles}
                </Popover>
            );

            style = 'default';
            if (user.isManager) {
                style = 'warning';
            }
            if (user.superRegion === 'EMEA') {
                geoStyle = 'primary';
            } else if (user.superRegion === 'APAC') {
                geoStyle = 'danger';
            } else if (user.superRegion === 'India') {
                geoStyle = 'success';
            } else if (user.superRegion === 'NA') {
                geoStyle = 'default';
            } else if (user.superRegion === 'LATAM') {
                geoStyle = 'warning';
            }
            title = <span><b>{`${user.superRegion}: ${user.fullName}`}</b></span>;
            skillMatrixMenuItem = user['skillMatrixId'] != null ? <MenuItem onSelect={this.skillMatrix} href={location.hash} key={`${user.kerberos}.skillMatrix`}>Open in SkillMatrix</MenuItem> : null;
            engineerReportMenuItem = user['skillMatrixId'] != null ? <MenuItem onSelect={this.engineerReport} href={location.hash} key={`${user.kerberos}.engineerReport`}>Engineer Report</MenuItem> : null;
            return (
                <OverlayTrigger trigger='hover' placement='right' overlay={popover}>
                    <DropdownButton bsStyle={style} bsSize={this.props.size || 'small'} title={title} onClick={this.openUser}>
                        <MenuItem onSelect={this.sendEmail} href={location.hash} key={`${user.kerberos}.email`}>Send E-Mail</MenuItem>
                        <MenuItem onSelect={this.salesForce} href={location.hash} key={`${user.kerberos}.sfdc`}>Open in Salesforce</MenuItem>
                        <MenuItem onSelect={this.calendar} href={location.hash} key={`${user.kerberos}.calendar`}>View Calendar</MenuItem>
                        {skillMatrixMenuItem }
                        {engineerReportMenuItem }
                    </DropdownButton>
                </OverlayTrigger>
            );
        }
    },
    // # TODO -- Drive this through props for Unified
    openUser: function() {
        var user;
        user = this.props.resource.resource;
        $(location).attr('href', "#User/" + (_.first(user.sso)));
        return false;
    },
    sendEmail: function() {
        var user;
        user = this.props.resource.resource;
        $(location).attr('href', "mailto:" + (_.find(user.email, function(email) {
            return email.addressType = 'PRIMARY';
        }).address));
        return false;
    },
    salesForce: function() {
        var user;
        user = this.props.resource;
        window.open("https://c.na7.visual.force.com/" + user.externalModelId, '_blank');
        return false;
    },
    //sendEmail: function() {
    //    var user;
    //    user = this.props.resource.resource;
    //    $(location).attr('hash', "#Calendar/user/" + user.kerberos);
    //    return false;
    //},
    skillMatrix: function() {
        var user;
        user = this.props.resource;
        window.open("http://skillmatrix-jtrantin.itos.redhat.com/member.jsf?id=" + user.resource.skillMatrixId, '_blank');
        return false;
    },
    engineerReport: function() {
        var user;
        user = this.props.resource.resource;
        if (moment().month() < 12) {
            $(location).attr('hash', "#EngineerReport/" + user.kerberos + "/" + (moment().year()) + "-" + (moment().month()) + "-01/" + (moment().year()) + "-" + (moment().month() + 1) + "-01");
        } else {
            $(location).attr('hash', "#EngineerReport/" + user.kerberos + "/" + (moment().year()) + "-" + (moment().month()) + "-01/" + (moment().year() + 1) + "-01-01");
        }
        return false;
    }
});
